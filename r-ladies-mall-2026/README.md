# Automatic NLP with LLMs Using `mall`

Talk given by Edgar Ruiz for R-Ladies (2026).

**Published presentation:** https://edgararuiz-automatic-nlp-mall-presentation.share.connect.posit.cloud/

## Overview

This talk introduces [`mall`](https://mlverse.github.io/mall/), an R package that brings LLM-powered NLP directly into a `dplyr` pipeline — no model training, no labeling, no per-task fine-tuning required. The talk covers sentiment analysis, summarization, classification, entity extraction, verification, translation, and custom prompts, all demonstrated on a small product-reviews dataset.

## Repository structure

```
.
├── presentation/
│   ├── automatic-nlp-with-mall.qmd   # Quarto RevealJS slide deck (source)
│   ├── automatic-nlp-with-mall.html  # Rendered slides
│   └── theme.scss                    # Custom reveal.js theme
├── demo/
│   ├── automatic-nlp-with-mall-demo.qmd   # Live-demo notebook (source)
│   └── automatic-nlp-with-mall-demo.html  # Rendered notebook
└── examples.rmarkdown   # Additional R Markdown examples
```

## Topics covered

- Sentiment analysis with `llm_sentiment()`
- Text summarization with `llm_summarize()`
- Classification with `llm_classify()`
- Entity extraction with `llm_extract()`
- Yes/no verification with `llm_verify()`
- Translation with `llm_translate()`
- Custom prompts with `llm_custom()`
- Vector counterparts (`llm_vec_*()`) for single-string use
- Multilingual end-to-end pipeline (detect → filter → translate → sentiment)

## Requirements

- R with the `mall` and `dplyr` packages installed
- [Ollama](https://ollama.com/) running locally with the `llama3.2` model (for the demo notebook)
