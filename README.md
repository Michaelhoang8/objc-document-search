# Offline document search

Build an in-memory inverted index and rank matching documents with BM25 using Foundation.

Language: **Objective-C**.

[![Validation](https://github.com/Michaelhoang8/objc-document-search/actions/workflows/ci.yml/badge.svg)](https://github.com/Michaelhoang8/objc-document-search/actions/workflows/ci.yml)

## Run

```sh
clang -fobjc-arc -Wall -Wextra -framework Foundation main.m -o document-search
./document-search fixtures/documents.json 'pipeline data'
```

## Behavior

- Canonical Unicode normalization and alphanumeric tokenization precede indexing.
- Repeated query words count once; results use deterministic ID tie-breaking.
- Ranks OR matches with BM25 k1=1.2 and b=0.75, including empty documents in corpus length statistics.

## Validation

```sh
./document-search --test
```

The workflow executes the checked-in fixtures and boundary tests. See the workflow log for the actual result; tests are included with the source.

## Scope

Requires macOS Foundation and Clang. No stemming, phrase queries, persistence or relevance benchmark claims. Tokens follow Unicode alphanumeric boundaries, not language-specific morphology.

Code: [MIT](LICENSE). Fixtures are constructed examples.
