/**
 * Embedder factory — returns the configured provider.
 */

import type { Embedder } from "./types.js";
import { OllamaEmbedder } from "./ollama.js";
import { OpenRouterEmbedder } from "./openrouter.js";
import { AzureOpenAIEmbedder } from "./azure-openai.js";

export type { Embedder, ThoughtMetadataExtracted } from "./types.js";

let _embedder: Embedder | null = null;

export function getEmbedder(): Embedder {
  if (!_embedder) {
    const provider = (process.env.EMBEDDER_PROVIDER ?? "ollama").toLowerCase();

    switch (provider) {
      case "ollama":
        _embedder = new OllamaEmbedder();
        break;
      case "openrouter":
        _embedder = new OpenRouterEmbedder();
        break;
      case "azure-openai":
        _embedder = new AzureOpenAIEmbedder();
        break;
      default:
        throw new Error(
          `Unknown embedder provider: "${provider}". Use "ollama", "openrouter", or "azure-openai".`
        );
    }
  }

  return _embedder;
}
