"""Tests for model catalog hydration from environment variables."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

from deeptutor.services.config.env_store import EnvStore
from deeptutor.services.config.model_catalog import ModelCatalogService


def test_hydrate_gemini_from_env(tmp_path: Path) -> None:
    """Test that Gemini settings in .env correctly hydrate the catalog with smart defaults."""
    env_path = tmp_path / ".env"
    env_path.write_text(
        "LLM_BINDING=gemini\n"
        "LLM_HOST=https://generativelanguage.googleapis.com/v1beta/openai/\n"
        "LLM_API_KEY=test-key-gemini\n"
        "EMBEDDING_BINDING=gemini\n"
        "EMBEDDING_HOST=https://generativelanguage.googleapis.com/v1beta/openai/\n"
        "EMBEDDING_API_KEY=test-key-gemini\n",
        encoding="utf-8"
    )
    
    catalog_path = tmp_path / "model_catalog.json"
    
    with patch("deeptutor.services.config.model_catalog.get_env_store") as mock_get_env:
        mock_get_env.return_value = EnvStore(path=env_path)
        
        service = ModelCatalogService(path=catalog_path)
        catalog = service.load()
        
        # Check Brain (LLM)
        llm = catalog["services"]["llm"]["profiles"][0]
        assert llm["binding"] == "gemini"
        assert llm["api_key"] == "test-key-gemini"
        # Verify smart default model
        assert llm["models"][0]["model"] == "gemini-1.5-flash"
        
        # Check Librarian (Embedding)
        emb = catalog["services"]["embedding"]["profiles"][0]
        assert emb["binding"] == "gemini"
        assert emb["api_key"] == "test-key-gemini"
        # Verify smart default model and CORRECT dimension (768 for Gemini)
        assert emb["models"][0]["model"] == "text-embedding-004"
        assert emb["models"][0]["dimension"] == "768"


def test_hydrate_openai_from_env(tmp_path: Path) -> None:
    """Test that OpenAI settings in .env correctly hydrate the catalog."""
    env_path = tmp_path / ".env"
    env_path.write_text(
        "LLM_BINDING=openai\n"
        "LLM_API_KEY=test-key-openai\n"
        "EMBEDDING_BINDING=openai\n"
        "EMBEDDING_API_KEY=test-key-openai\n",
        encoding="utf-8"
    )
    
    catalog_path = tmp_path / "model_catalog.json"
    
    with patch("deeptutor.services.config.model_catalog.get_env_store") as mock_get_env:
        mock_get_env.return_value = EnvStore(path=env_path)
        
        service = ModelCatalogService(path=catalog_path)
        catalog = service.load()
        
        # Check Brain
        llm = catalog["services"]["llm"]["profiles"][0]
        assert llm["binding"] == "openai"
        assert llm["models"][0]["model"] == "gpt-4o-mini"
        
        # Check Librarian
        emb = catalog["services"]["embedding"]["profiles"][0]
        assert emb["binding"] == "openai"
        assert emb["models"][0]["dimension"] == "3072"


def test_hydrate_ollama_from_env(tmp_path: Path) -> None:
    """Test that Ollama (local) settings correctly hydrate."""
    env_path = tmp_path / ".env"
    env_path.write_text(
        "LLM_BINDING=ollama\n"
        "LLM_HOST=http://localhost:11434/v1\n"
        "LLM_API_KEY=ollama\n"
        "EMBEDDING_BINDING=ollama\n"
        "EMBEDDING_HOST=http://localhost:11434\n"
        "EMBEDDING_API_KEY=ollama\n",
        encoding="utf-8"
    )
    
    catalog_path = tmp_path / "model_catalog.json"
    
    with patch("deeptutor.services.config.model_catalog.get_env_store") as mock_get_env:
        mock_get_env.return_value = EnvStore(path=env_path)
        
        service = ModelCatalogService(path=catalog_path)
        catalog = service.load()
        
        # Check Librarian defaults for Ollama
        emb = catalog["services"]["embedding"]["profiles"][0]
        assert emb["binding"] == "ollama"
        assert emb["models"][0]["model"] == "nomic-embed-text"
        assert emb["models"][0]["dimension"] == "768"


def test_hydrate_mixed_providers_from_env(tmp_path: Path) -> None:
    """Test that mixed providers (Gemini for Brain, OpenAI for Librarian) hydrate correctly."""
    env_path = tmp_path / ".env"
    env_path.write_text(
        "LLM_BINDING=gemini\n"
        "LLM_API_KEY=key-gemini\n"
        "EMBEDDING_BINDING=openai\n"
        "EMBEDDING_API_KEY=key-openai\n",
        encoding="utf-8"
    )
    
    catalog_path = tmp_path / "model_catalog.json"
    
    with patch("deeptutor.services.config.model_catalog.get_env_store") as mock_get_env:
        mock_get_env.return_value = EnvStore(path=env_path)
        
        service = ModelCatalogService(path=catalog_path)
        catalog = service.load()
        
        # Brain should be Gemini
        llm = catalog["services"]["llm"]["profiles"][0]
        assert llm["binding"] == "gemini"
        assert llm["models"][0]["model"] == "gemini-1.5-flash"
        
        # Librarian should be OpenAI
        emb = catalog["services"]["embedding"]["profiles"][0]
        assert emb["binding"] == "openai"
        assert emb["models"][0]["dimension"] == "3072"
        assert emb["models"][0]["model"] == "text-embedding-3-large"
