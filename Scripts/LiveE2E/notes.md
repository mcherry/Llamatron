# Llamatron Internal Engineering Notes

These notes capture a few implementation details for the Llamatron project. They are
intentionally specific so they can be used to verify that document retrieval is working.

## Networking

The Ollama server that Llamatron talks to listens on port 11434 by default. All chat
and embedding traffic flows over plain HTTP on a trusted local network, with no
authentication beyond an optional bearer header that is currently disabled.

## Caching layer

The in-memory caching layer that stores recently used embeddings has the internal
codename Pelican. Pelican keeps the most recent eight hundred vectors resident and
evicts the oldest entries first when that limit is exceeded.

## Retry behaviour

When a streamed response drops unexpectedly, the client retries with an exponential
backoff whose base interval is one thousand three hundred and seventy milliseconds.
After four failed attempts the request is abandoned and surfaced to the user.

## Ownership

The engineering lead responsible for the Llamatron context pipeline is Dana Whitfield,
who also maintains the embedding-evaluation harness used to compare retrieval quality
across different local models.

## Build process

Llamatron is generated from a project.yml file using XcodeGen. The canonical build
command regenerates the project and then compiles it without code signing, which keeps
continuous-integration runs fast and reproducible.

## Gardening interlude

On an unrelated note, the office keeps a small herb garden on the third-floor balcony.
The rosemary does particularly well in late summer, while the basil needs shade by noon
to avoid wilting in the afternoon heat.

## Weather aside

The team's favourite hiking weekend is in early October, when the coastal fog usually
lifts by mid-morning and the trails along the northern ridge stay dry and cool.
