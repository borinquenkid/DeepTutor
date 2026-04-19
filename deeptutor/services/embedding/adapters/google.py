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

    async def negotiate(self) -> Dict[str, Any]:
        """Probes the Google API to find the best available embedding model."""
        base = self.base_url.rstrip('/')
        if "/v1" not in base:
            base = f"{base}/v1beta"
        
        url = f"{base}/models"
        params = {"key": self.api_key}
        
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(url, params=params)
                if response.status_code == 200:
                    data = response.json()
                    models = [m for m in data.get("models", []) if "embed" in m["name"].lower()]
                    
                    if not models:
                         return {"model": self.model, "dimensions": self.dimensions}
                         
                    # Sort to favor gemini-embedding-001
                    best_model = None
                    for name in ["models/gemini-embedding-001", "models/text-embedding-004"]:
                        if any(m["name"] == name for m in models):
                            best_model = name
                            break
                    
                    if not best_model:
                        best_model = models[0]["name"]
                    
                    # Resolve dimensions
                    model_meta = next((m for m in models if m["name"] == best_model), {})
                    dims = model_meta.get("outputTokenLimit") or 3072 # Fallback
                    
                    # Special cases for known models
                    clean_name = best_model.replace("models/", "")
                    if "gemini-embedding-001" in best_model:
                        dims = 3072
                    elif "text-embedding-004" in best_model:
                        dims = 768

                    return {
                        "model": clean_name,
                        "dimensions": dims,
                        "provider": "google"
                    }
        except Exception:
            pass
            
        return {"model": self.model, "dimensions": self.dimensions}
