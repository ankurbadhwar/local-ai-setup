# Local AI Coding Setup

A small, reproducible setup for running a local coding model with llama.cpp
and using it from coding agents/editors.

Current stack:

- **llama.cpp** for inference
- **Qwen3-Coder 30B A3B Q4_K_M** as the model
- **Kilo Code** (VS Code) and **OpenCode** (Zed) as coding agents
- **i3** for the desktop
- a **systemd user service** for the model server

The model is exposed through llama.cpp's OpenAI-compatible API on
`127.0.0.1:8080`.

Two agent harnesses because I switch between VS Code and Zed depending on
the task, and Kilo and OpenCode each only work in one of them. Both talk to
the same local server, so switching editors doesn't mean switching models.

## Quick start

Assumes NVIDIA drivers, CUDA and a CUDA-enabled llama.cpp build are already
working.

```bash
git clone <repository-url>
cd local-ai-setup
./install.sh
```

Start the model:

```bash
systemctl --user start llama-server
```

Check that the expected model and context are loaded:

```bash
curl -s http://127.0.0.1:8080/props \
  | python3 -m json.tool \
  | grep -E '"n_ctx"|model_alias'
```

Then start Kilo or OpenCode.

## Prerequisites

- A supported NVIDIA GPU
- Working NVIDIA proprietary drivers
- CUDA properly installed/configured
- A working `nvidia-smi`
- A CUDA-enabled build of llama.cpp

Sanity check:

```bash
nvidia-smi
```
If `nvidia-smi` doesn't work, fix the NVIDIA/CUDA setup before continuing.
This repo won't install or configure the NVIDIA driver stack for you.

## Hardware used for testing

- AMD Ryzen 5 7600X
- NVIDIA GeForce RTX 4070 12GB
- 32GB RAM
- Debian 13, i3
- NVIDIA driver 610.57.04 / CUDA 13.3

Nothing here is hardware-specific, but the binding constraint is memory — a
30B model at this quantization means GPU VRAM, system RAM and context size
all matter.

## Model

**Qwen3-Coder 30B A3B — Q4_K_M**

Model page:
https://huggingface.co/lucataco/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M-GGUF

llama.cpp downloads the model directly; GGUF files aren't in this repo.

`30B A3B` = Mixture-of-Experts, ~30B total parameters, ~3B active per token.

## llama.cpp

Build it separately: https://github.com/ggml-org/llama.cpp

The installer expects the binary at:

```text
~/src/llama.cpp/build/bin/llama-server
```

If yours lives elsewhere:

```bash
LLAMA_SERVER=/path/to/llama-server ./install.sh
```

This repo intentionally doesn't build llama.cpp itself — keeping it separate
means the setup isn't pinned to one particular build.

## Configuration

```text
Model:            Qwen3-Coder 30B A3B Q4_K_M
Context:          131072 tokens
Parallel slots:   1
GPU layers:       auto
Flash Attention:  enabled
KV cache K:       Q4_0
KV cache V:       Q4_0
KV offload:       enabled
Memory fitting:   enabled
Host:             127.0.0.1
Port:             8080
Web UI:           disabled
```

Config file: `llama/config/qwen3-coder-30b-q4.conf`

Server listens on localhost only — it's not meant to be exposed to the LAN
or internet.

## Why Q4 KV cache?

A 128K context eats memory fast, and the KV cache grows as that context
actually gets used. Q8 KV is more precise but noticeably heavier; on a
12GB RTX 4070, Q4_0 KV is what makes the full 128K window practical. There's
a quality cost at very long contexts, but for coding work the extra memory
headroom wins.

## Performance

Measured on the final 128K (131,072-token) config. Reference numbers, not
guarantees — context length, prompt size, GPU state, and sampler settings
all move these around.

**Simple coding generation**
```text
Prompt:             31 tokens
Generation:         500 tokens
Prompt processing:  ~115 tok/s
Generation:         ~56 tok/s
```

**Agent-style coding**
```text
Prompt:             62 tokens
Generation:         1000 tokens
Prompt processing:  ~243 tok/s
Generation:         ~51 tok/s
```

**Tool-call test**
```text
Prompt:             283 tokens
Generation:         24 tokens
Prompt processing:  ~677 tok/s
Generation:         ~54 tok/s
```

## Why Qwen3-Coder over Qwen2.5-Coder 14B

The original setup ran Qwen2.5-Coder 14B Q4_K_M — fast, comfortable on
12GB VRAM, fine for ordinary code generation. It fell apart as an *agent*
rather than a chatbot: the goal wasn't "give me some code," it was "work
inside my repo, run commands, edit files, test, iterate," which depends on
reliable tool calling.

Given a tool definition for a `bash` function and the prompt
`Use the bash tool to run pytest --version`. In this llama.cpp/API setup, Qwen2.5-Coder 14B didn't return
a structured tool call — it generated text that merely looked like one:

```text
<tools>
{"name": "bash", "arguments": {"command": "pytest --version"}}
</tools>
```

Prompting it to use a specific `<tool_call>` tag changed the output format
but not the underlying issue: it was still plain assistant text, not an
actual `tool_calls` object the client could execute.

Qwen3-Coder 30B A3B, tested the same way, returned a proper OpenAI-style
response:

```json
{
  "tool_calls": [
    {
      "type": "function",
      "function": {
        "name": "bash",
        "arguments": "{\"command\":\"pytest --version\"}"
      }
    }
  ]
}
```

That held up beyond the raw `curl` test too — connected to Kilo, it invoked
tools, worked in the actual dev environment, and fixed a broken file
end-to-end. That's what settled it: not benchmark scores, but whether the
model could actually drive an agent workflow.

The tradeoff is real. The 14B model left plenty of VRAM to spare; 30B A3B
pushes the RTX 4070 much harder and needs the memory tuning above (Q4_0 KV,
Flash Attention, careful context sizing) to fit at 128K. Worth it, but not
free.

Final config: Qwen3-Coder 30B A3B, Q4_K_M, 128K context, Q4_0 KV cache,
Flash Attention.

## Running llama-server

Managed as a systemd user service:

```bash
systemctl --user start llama-server
systemctl --user stop llama-server
systemctl --user restart llama-server
systemctl --user status llama-server
```

Logs:

```bash
journalctl --user -u llama-server -f
```

Service file: `~/.config/systemd/user/llama-server.service`

Not enabled at boot by default (it holds a lot of GPU memory). To enable:

```bash
systemctl --user enable llama-server
```

## i3 toggle

`llama/scripts/toggle-llama.sh` starts the server if it's stopped and stops
it if it's running. Bound to `Ctrl+V` in the working i3 config, so the model
can be flipped on without a terminal.

Installed to: `~/.config/i3/scripts/toggle-llama`

The actual keybinding is left to your own i3 config.

### If you don't use i3

The toggle script doesn't depend on i3 at all — the install path just
reflects where the installer happens to put it. Works the same on KDE,
GNOME, Hyprland, Sway, or nothing in particular:

```bash
systemctl --user start llama-server
systemctl --user stop llama-server
systemctl --user restart llama-server
# or, directly:
~/.config/i3/scripts/toggle-llama
```

Bind that script to whatever shortcut mechanism your DE/WM uses, or skip it
and just use `systemctl --user`.

## Kilo Code

Used from VS Code. Points at llama.cpp's OpenAI-compatible endpoint:
`http://127.0.0.1:8080/v1`

Example config: `kilo/kilo.jsonc.example`

Bash permission is enabled by design — the point of this setup is letting
the agent touch the dev environment. Review those permissions before
reusing this config elsewhere.

## OpenCode

Used from Zed, since Kilo doesn't run there. Config:
`opencode/opencode.jsonc.example` — deliberately minimal.

## Zed

Personal Zed config isn't included. The model backend is independent of the
editor, so anything that speaks the OpenAI-compatible API can use this
server — Kilo/VS Code and OpenCode/Zed are just the two combinations
actually in use.

## API

Endpoint: `http://127.0.0.1:8080/v1`

Check the server:

```bash
curl -s http://127.0.0.1:8080/props | python3 -m json.tool
```

Model/context check:

```bash
curl -s http://127.0.0.1:8080/props \
  | python3 -m json.tool \
  | grep -E '"n_ctx"|model_alias'
```

Current setup reports:

```text
"n_ctx": 131072
"model_alias": "lucataco/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M-GGUF:Q4_K_M"
```

Basic request:

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "lucataco/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M-GGUF:Q4_K_M",
    "messages": [
      {"role": "user", "content": "Explain RAII in modern C++."}
    ],
    "temperature": 0.2,
    "max_tokens": 500
  }'
```

## Installation

```bash
git clone <repository-url>
cd local-ai-setup
./install.sh
```

Installs into:

```text
~/AI/config/
~/AI/scripts/
~/.config/systemd/user/
~/.config/i3/scripts/
~/.config/kilo/
~/.config/opencode/
```

It does **not** build llama.cpp, download the model, start llama-server, or
restart an already-running server.

### Custom AI directory

Default install location is `~/AI`. Override with:

```bash
AI_DIR=/some/path ./install.sh
```

### Custom llama-server location

```bash
LLAMA_SERVER=/some/path/llama-server ./install.sh
```

Both variables can be combined.

## Backups

Existing files are backed up before being overwritten, under:

```text
~/.local/share/local-ai-setup/backups/
```

Each install run gets its own timestamped directory, so a bad update is
recoverable.

## Updating

```bash
git pull
./install.sh
```

The installer doesn't restart llama-server — do that yourself if the config
changed:

```bash
systemctl --user restart llama-server
```

## Memory

The RTX 4070's 12GB is close to the practical ceiling for this config;
llama-server used roughly 10–11GB of VRAM in testing, depending on state.
System RAM adds headroom, but swap shouldn't be part of the normal inference
path — if it's constantly swapping, something in the config needs
attention. Note that 128K is a *maximum* context window, not something every
request consumes in full.

## Speculative decoding

Tested and dropped. The only EAGLE-3 checkpoint available was built for the
base Qwen3 30B A3B target, not the Qwen3-Coder variant used here, and wasn't
even in GGUF form. Speculative drafts are target-specific, so forcing an
incompatible one in wasn't worth it — final config uses normal generation.

## Repository layout

```text
local-ai-setup/
├── README.md
├── LICENSE
├── .gitignore
├── install.sh
│
├── llama/
│   ├── config/
│   │   └── qwen3-coder-30b-q4.conf
│   ├── scripts/
│   │   ├── start-llama-server.sh
│   │   └── toggle-llama.sh
│   └── systemd/
│       └── llama-server.service
│
├── kilo/
│   └── kilo.jsonc.example
│
└── opencode/
    └── opencode.jsonc.example
```

Model files, caches, logs, databases and personal editor config are
deliberately excluded.

## Notes

This repo is the glue around the model, not the model itself or llama.cpp.
Performance numbers are from one machine — treat them as a reference point,
not a benchmark for every system. Primarily built for local software
development and coding agents.

## License

Configuration, scripts and documentation here are MIT licensed. llama.cpp,
Qwen3-Coder and other third-party components have their own licenses —
check their repos/model cards.
