# CueMe — Product Vision

> Your life, available when you need it.

## Why this, why now

People already produce the raw material of a remarkable personal memory: notes,
meetings, interviews, decisions, voice memos and the thoughts that appear between
them. The material is fragmented across tools and usually becomes inert. A note
app waits for perfect discipline; a meeting recorder remembers only the meeting;
an AI assistant knows the current prompt but not the life behind it.

CueMe is a **personal second brain that is present while life happens**. It makes
writing pleasurable, turns audio into structured memory, and can bring a small,
relevant part of that memory back during a demanding conversation.

## The problem

- Valuable experiences disappear because capturing and organizing them costs
  attention at exactly the wrong time.
- Notes are easy to create and hard to consume later, so they become a graveyard.
- Meeting tools produce isolated transcripts instead of a continuous personal
  history.
- Under pressure—especially in interviews—people cannot retrieve all the examples,
  confidence and hard-earned context they already possess.
- Hosted knowledge tools can lock the user into a database, pricing model or cloud
  policy they do not control.

## The product

The base object is a **Memory Note**. It can be a written page, journal entry,
meeting, interview, sales call, imported voice memo, or any combination of text,
recording, transcript, Coach cards, decisions, actions and attachments.

Projects are folders. Notes are folders. The note itself is Markdown with
frontmatter. Audio and attachments live beside it. Those files are the source of
truth; SQLite, FTS5, embeddings and sqlite-vec are disposable indexes that make
the files fast and intelligent.

Recording, transcription, summaries and Coach are not a separate product bolted
onto the library. They are **accelerators for making a durable note**:

- write an idea or journal entry in a beautiful Markdown workspace;
- record a thought before it disappears;
- capture both sides of a conversation and preserve the evidence;
- let the selected LLM name and structure the memory;
- connect it to projects and cross-cutting labels;
- retrieve related memories semantically;
- opt in to using those real memories as grounded context for the live Coach.

## Principles

- **The user owns the corpus.** A normal filesystem tree remains useful without
  CueMe. No database export ritual is required.
- **Files are truth; indexes are acceleration.** SQLite and vectors may be deleted
  and rebuilt at any time without losing knowledge.
- **Capture should be easier than forgetting.** Writing, journaling, audio import
  and live recording are first-class entry points from the home screen.
- **Reading is part of writing.** A calm, typographic block editor should feel
  finished while typing; Markdown syntax stays available without getting between
  the person and the thought.
- **Intelligence preserves provenance.** Generated titles never overwrite a user
  rename. Decisions and answers link back to evidence. AI enriches the note but
  does not become its owner.
- **Memory use is explicit and bounded.** The Coach may receive a small local
  selection of relevant notes only when the user enables it; ambient CLI context
  remains forbidden.
- **Local-first by default.** On-device STT, translation and embeddings remain the
  defaults. Deepgram and DeepSeek are optional, keyed choices.
- **Live help must be glanceable.** During a conversation, one specific cue beats
  a wall of analysis.
- **Interview confidence matters.** CueMe helps people retrieve their actual
  experience when pressure, language or timidity makes it temporarily inaccessible.

## What 1.0 means

CueMe 1.0 is the point where the library, not the recorder, is the center of the
product. It includes file-first Memory Notes and Project folders, frontmatter,
labels, attachments, visual block editing with canonical Markdown, meaningful LLM-generated
titles, user renaming, local hybrid search, system/light/dark themes, explicit
profiles on home, audio journaling, and opt-in relevant-memory grounding for the
live Coach—while preserving the existing capture, transcription, translation,
minutes, interview training, playback, import and reliability features.

## Non-goals for 1.0

- No collaborative team workspace or server-owned account system.
- No iOS, Windows or web editor; macOS 26 remains the supported platform.
- No mandatory cloud STT, translation, embeddings or storage.
- No proprietary document format as the primary corpus.
- No automatic publishing of private notes to any model or service.

## Related docs

- [Architecture](ARCHITECTURE.md) · [Abstractions](ABSTRACTIONS.md) · [ADRs](adr/README.md)
