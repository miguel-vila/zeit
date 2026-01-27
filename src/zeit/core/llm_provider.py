"""LLM provider abstraction for multi-provider support."""

import logging
import os
from abc import ABC, abstractmethod

logger = logging.getLogger(__name__)


class LLMProvider(ABC):
    """Abstract base class for LLM providers."""

    @abstractmethod
    def generate(self, prompt: str, temperature: float = 0.7) -> str:
        """Generate text completion.

        Args:
            prompt: The prompt to send to the model
            temperature: Sampling temperature (0.0 to 1.0)

        Returns:
            Generated text response
        """
        ...


class OllamaProvider(LLMProvider):
    """Ollama LLM provider."""

    def __init__(self, model: str, base_url: str | None = None) -> None:
        from ollama import Client

        self.client = Client(host=base_url) if base_url else Client()
        self.model = model
        logger.debug(f"Initialized OllamaProvider with model={model}")

    def generate(self, prompt: str, temperature: float = 0.7) -> str:
        response = self.client.generate(
            model=self.model,
            prompt=prompt,
            options={"temperature": temperature},
        )
        return response.response


class OpenAIProvider(LLMProvider):
    """OpenAI LLM provider."""

    def __init__(self, model: str, api_key: str | None = None) -> None:
        from openai import OpenAI

        # Use provided key, or fall back to env var
        resolved_key = api_key or os.environ.get("OPENAI_API_KEY")
        if not resolved_key:
            raise ValueError(
                "OpenAI API key required. Set OPENAI_API_KEY env var or provide api_key."
            )

        self.client = OpenAI(api_key=resolved_key)
        self.model = model
        logger.debug(f"Initialized OpenAIProvider with model={model}")

    def generate(self, prompt: str, temperature: float = 0.7) -> str:
        response = self.client.chat.completions.create(
            model=self.model,
            messages=[{"role": "user", "content": prompt}],
            temperature=temperature,
        )
        return response.choices[0].message.content or ""
