"""Native Google (Gemini) embedding adapter."""

import logging
from typing import Any, Dict

import httpx

from .base import BaseEmbeddingAdapter, EmbeddingRequest, EmbeddingResponse

logger = logging.getLogger(__name__)


class GoogleEmbeddingAdapter(BaseEmbeddingAdapter):
    """
    Adapter for Google Generative AI (Gemini) embedding models.
    
    API docs: https://ai.google.dev/api/rest/v1beta/models/embedContent
    """

    async def embed(self, request: EmbeddingRequest) -> EmbeddingResponse:
        model = request.model or self.model
        if not model:
            model = "gemini-embedding-001"
            
        # Clean model name - ensure it has the models/ prefix
        full_model_name = f"models/{model}" if not model.startswith("models/") else model
        
        # Use the absolute root to avoid any path doubling issues
        # Endpoint: POST https://generativelanguage.googleapis.com/v1beta/{model}:embedContent?key={api_key}
        url = f"https://generativelanguage.googleapis.com/v1beta/{full_model_name}:embedContent"
        
        params = {"key": self.api_key}
        headers = {"Content-Type": "application/json"}
        headers.update({str(k): str(v) for k, v in self.extra_headers.items()})

        embeddings = []
        timeout = httpx.Timeout(connect=10.0, read=max(self.request_timeout, 60), write=10.0, pool=10.0)
        
        async with httpx.AsyncClient(timeout=timeout) as client:
            for text in request.texts:
                # Payload for singular :embedContent
                payload = {
                    "content": {
                        "parts": [{"text": text}]
                    }
                }
                
                response = await client.post(url, json=payload, params=params, headers=headers)
                
                if response.status_code != 200:
                    logger.error(f"Google Embedding Error {response.status_code}: {response.text}")
                    # Try a fallback to 'v1' if 'v1beta' failed
                    if response.status_code == 404:
                        url_v1 = url.replace("/v1beta/", "/v1/")
                        response = await client.post(url_v1, json=payload, params=params, headers=headers)
                
                response.raise_for_status()
                data = response.json()
                embeddings.append(data["embedding"]["values"])

        return EmbeddingResponse(
            embeddings=embeddings,
            model=model,
            dimensions=len(embeddings[0]) if embeddings else 0,
            usage={}
        )

    def get_model_info(self) -> Dict[str, Any]:
        return {
            "model": self.model,
            "dimensions": self.dimensions or 768,
            "provider": "google",
        }
