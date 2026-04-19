"""Native Google (Gemini) embedding adapter."""

import logging
from typing import Any, Dict

import httpx

from .base import BaseEmbeddingAdapter, EmbeddingRequest, EmbeddingResponse

logger = logging.getLogger(__name__)


class GoogleEmbeddingAdapter(BaseEmbeddingAdapter):
    """
    Adapter for Google Generative AI (Gemini) embedding models.
    
    API docs: https://ai.google.dev/api/rest/v1beta/models/batchEmbedContents
    """

    async def embed(self, request: EmbeddingRequest) -> EmbeddingResponse:
        # Google native endpoint for batch embeddings:
        # POST https://generativelanguage.googleapis.com/v1beta/models/{model}:batchEmbedContents
        
        model = request.model or self.model
        if not model:
            model = "text-embedding-004"
            
        base = self.base_url.rstrip('/')
        # Ensure we are at the models root
        if "/models" not in base and not base.endswith("/v1beta") and not base.endswith("/v1"):
             url = f"{base}/models/{model}:batchEmbedContents"
        else:
             # If user already provided a full path, or just the base
             if ":batchEmbedContents" in base:
                 url = base
             else:
                 url = f"{base}/{model}:batchEmbedContents"

        # Handle API key. Google native uses 'x-goog-api-key' header or 'key' query param.
        headers = {
            "Content-Type": "application/json",
            "x-goog-api-key": self.api_key
        }
        headers.update({str(k): str(v) for k, v in self.extra_headers.items()})

        # Google schema: {"requests": [{"model": "models/...", "content": {"parts": [{"text": "..."}]}}]}
        # For simplicity, we use the model name provided or default
        full_model_name = f"models/{model}" if not model.startswith("models/") else model
        
        payload = {
            "requests": [
                {
                    "model": full_model_name,
                    "content": {"parts": [{"text": text}]}
                } for text in request.texts
            ]
        }

        timeout = httpx.Timeout(
            connect=10.0,
            read=max(self.request_timeout, 60),
            write=10.0,
            pool=10.0,
        )

        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.post(url, json=payload, headers=headers)
            if response.status_code >= 400:
                logger.error(f"Google Embedding HTTP {response.status_code}: {response.text}")
            response.raise_for_status()
            data = response.json()

        # Extract embeddings from Google response
        # Schema: {"embeddings": [{"values": [...]}, ...]}
        try:
            vectors = [item["values"] for item in data.get("embeddings", [])]
        except (KeyError, TypeError) as exc:
            keys = list(data.keys()) if isinstance(data, dict) else "not-a-dict"
            raise ValueError(f"Failed to parse Google embedding response. Keys={keys}") from exc

        if not vectors:
            raise ValueError("Google embedding response parsed but no vectors found.")

        actual_dims = len(vectors[0])
        
        return EmbeddingResponse(
            embeddings=vectors,
            model=model,
            dimensions=actual_dims,
            usage={} # Google doesn't provide detailed usage in this response usually
        )

    def get_model_info(self) -> Dict[str, Any]:
        return {
            "model": self.model,
            "dimensions": self.dimensions or 768,
            "provider": "google",
        }
