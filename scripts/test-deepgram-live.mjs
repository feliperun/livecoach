import fs from "node:fs";

const apiKey = process.env.DEEPGRAM_API_KEY;
const audioPath = process.argv[2];
if (!apiKey || !audioPath) {
  console.error("usage: DEEPGRAM_API_KEY=... node scripts/test-deepgram-live.mjs <pcm16-wave-file>");
  process.exit(2);
}

const wave = fs.readFileSync(audioPath);
const pcm = waveData(wave);
const params = new URLSearchParams({
  model: "nova-3",
  language: "pt-BR",
  encoding: "linear16",
  sample_rate: "16000",
  channels: "1",
  interim_results: "true",
  endpointing: "300",
  utterance_end_ms: "1000",
  punctuate: "true",
  smart_format: "true",
});
const socket = new WebSocket(`wss://api.deepgram.com/v1/listen?${params}`, ["token", apiKey]);
const startedAt = performance.now();
const finalSegments = [];

const timeout = setTimeout(() => fail("Deepgram live test timed out"), 15_000);
socket.addEventListener("open", () => {
  socket.send(pcm);
  setTimeout(() => socket.send(JSON.stringify({ type: "CloseStream" })), 600);
});
socket.addEventListener("message", ({ data }) => {
  const message = JSON.parse(String(data));
  if (message.type === "Results" && message.is_final) {
    const text = message.channel?.alternatives?.[0]?.transcript?.trim();
    if (text) finalSegments.push(text);
  }
});
socket.addEventListener("close", () => {
  clearTimeout(timeout);
  const transcript = finalSegments.join(" ").trim();
  if (!transcript) fail("Deepgram returned no final transcript");
  console.log(`Deepgram live: ok (${Math.round(performance.now() - startedAt)} ms)`);
  console.log(`Transcript: ${transcript}`);
});
socket.addEventListener("error", () => fail("Deepgram WebSocket failed"));

function waveData(buffer) {
  if (buffer.toString("ascii", 0, 4) !== "RIFF" || buffer.toString("ascii", 8, 12) !== "WAVE") {
    throw new Error("Expected a PCM WAVE file");
  }
  let offset = 12;
  while (offset + 8 <= buffer.length) {
    const id = buffer.toString("ascii", offset, offset + 4);
    const length = buffer.readUInt32LE(offset + 4);
    if (id === "data") return buffer.subarray(offset + 8, offset + 8 + length);
    offset += 8 + length + (length % 2);
  }
  throw new Error("WAVE data chunk not found");
}

function fail(message) {
  clearTimeout(timeout);
  console.error(message);
  try { socket.close(); } catch {}
  process.exitCode = 1;
}
