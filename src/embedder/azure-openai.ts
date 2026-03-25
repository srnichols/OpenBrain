/**
 * Azure OpenAI embedder — uses Azure-hosted OpenAI models.
 * For cloud deployments where Ollama is not available.
 */

import {
  type Embedder,
  type ThoughtMetadataExtracted,
  DEFAULT_METADATA,
  METADATA_PROMPT,
} from "./types.js";

export class AzureOpenAIEmbedder implements Embedder {
  private readonly endpoint: string;
  private readonly apiKey: string;
  private readonly embedDeployment: string;
  private readonly llmDeployment: string;
  private readonly apiVersion: string;

  constructor() {
    this.endpoint = process.env.AZURE_OPENAI_ENDPOINT ?? "";
    this.apiKey = process.env.AZURE_OPENAI_KEY ?? "";
    this.embedDeployment =
      process.env.AZURE_OPENAI_EMBED_DEPLOYMENT ?? "text-embedding-3-small";
    this.llmDeployment =
      process.env.AZURE_OPENAI_LLM_DEPLOYMENT ?? "gpt-4o-mini";
    this.apiVersion = process.env.AZURE_OPENAI_API_VERSION ?? "2024-06-01";

    if (!this.endpoint) {
      throw new Error(
        "AZURE_OPENAI_ENDPOINT is required when using azure-openai provider"
      );
    }
    if (!this.apiKey) {
      throw new Error(
        "AZURE_OPENAI_KEY is required when using azure-openai provider"
      );
    }

    console.log(
      `[embedder] Azure OpenAI (embed: ${this.embedDeployment}, llm: ${this.llmDeployment}, endpoint: ${this.endpoint})`
    );
  }

  async generateEmbedding(text: string): Promise<number[]> {
    const url = `${this.endpoint}/openai/deployments/${this.embedDeployment}/embeddings?api-version=${this.apiVersion}`;

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "api-key": this.apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ input: text }),
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(
        `Azure OpenAI embed failed: ${response.status} ${response.statusText} — ${body}`
      );
    }

    const data = (await response.json()) as {
      data: Array<{ embedding: number[] }>;
    };
    const embedding = data.data[0]?.embedding;

    if (!embedding) {
      throw new Error("Azure OpenAI returned empty embedding");
    }

    return embedding;
  }

  async extractMetadata(content: string): Promise<ThoughtMetadataExtracted> {
    const url = `${this.endpoint}/openai/deployments/${this.llmDeployment}/chat/completions?api-version=${this.apiVersion}`;

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "api-key": this.apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        messages: [
          { role: "system", content: METADATA_PROMPT },
          { role: "user", content },
        ],
        response_format: { type: "json_object" },
      }),
    });

    if (!response.ok) {
      console.warn(
        `[embedder] Azure OpenAI metadata extraction failed: ${response.status}`
      );
      return DEFAULT_METADATA;
    }

    const data = (await response.json()) as {
      choices: Array<{ message: { content: string } }>;
    };

    try {
      const raw = data.choices[0]?.message.content ?? "{}";
      const parsed = JSON.parse(raw) as ThoughtMetadataExtracted;
      return {
        type: parsed.type ?? "observation",
        topics: parsed.topics ?? [],
        people: parsed.people ?? [],
        action_items: parsed.action_items ?? [],
        dates: parsed.dates ?? [],
      };
    } catch (e) {
      console.warn("[embedder] Failed to parse metadata JSON:", e);
      return DEFAULT_METADATA;
    }
  }
}
