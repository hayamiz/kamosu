#!/usr/bin/env python3
"""
stream-monitor.py — Claude Code stream-json monitor for kamosu.

Reads JSONL from stdin (claude -p --output-format stream-json --verbose),
shows a spinner on stderr, writes raw events to a log file, and prints
a human-readable (or JSON) summary on stdout.

Exit codes:
  0 — success (result.subtype == "success", no errors)
  1 — failure (error, permission denials, or no useful work done)
"""

import argparse
import json
import os
import signal
import sys
import time


# Handle SIGPIPE gracefully (bash caller may exit early)
signal.signal(signal.SIGPIPE, signal.SIG_DFL)

SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧"]

TOOL_DISPLAY_KEY = {
    "Read": "file_path",
    "Edit": "file_path",
    "Write": "file_path",
    "Bash": "command",
    "Grep": "pattern",
    "Glob": "pattern",
}


def get_terminal_width():
    try:
        return os.get_terminal_size(2).columns
    except (ValueError, OSError):
        return 80


def detect_phase(tool_name, tool_input):
    """Determine high-level phase from tool usage."""
    path = tool_input.get("file_path", tool_input.get("path", ""))
    if tool_name == "Read" and ("raw/" in path or "ingest-queue" in path or path.endswith(".pdf")):
        return "Reading source files..."
    if tool_name in ("Read", "Grep", "Glob") and "wiki/" in path:
        return "Analyzing existing wiki..."
    if tool_name in ("Write", "Edit") and "concepts/" in path:
        return "Writing articles..."
    if tool_name in ("Write", "Edit") and (
        "_master_index" in path
        or "_category/" in path
        or "_cross_ref" in path
        or "_log.md" in path
    ):
        return "Updating indexes..."
    if tool_name == "Bash":
        return "Extracting text from PDF..."
    if tool_name == "Read":
        return "Reading files..."
    return f"Using {tool_name}..."


class StreamMonitor:
    def __init__(self, log_path, show_spinner=True, json_summary=False):
        self.log_path = log_path
        self.show_spinner = show_spinner
        self.json_summary = json_summary

        self.spinner_idx = 0
        self.current_phase = "Initializing..."
        self.start_time = time.time()

        # Tracking
        self.result_event = None
        self.articles_created = 0
        self.articles_updated = 0
        self.tool_uses = []
        self.malformed_lines = 0

    def run(self):
        log_dir = os.path.dirname(self.log_path)
        if log_dir:
            os.makedirs(log_dir, exist_ok=True)

        with open(self.log_path, "w") as log_file:
            for line in sys.stdin:
                raw = line.rstrip("\n")
                if not raw.strip():
                    continue

                # Always write to log
                log_file.write(raw + "\n")
                log_file.flush()

                # Parse
                try:
                    event = json.loads(raw)
                except json.JSONDecodeError:
                    self.malformed_lines += 1
                    continue

                self.process_event(event)

        # Clear spinner line
        if self.show_spinner:
            self._clear_spinner()

        return self.finalize()

    def process_event(self, event):
        etype = event.get("type", "")

        if etype == "system":
            self.current_phase = "Initializing..."
            self._update_spinner()

        elif etype == "assistant":
            message = event.get("message", {})
            content = message.get("content", [])
            for block in content:
                if block.get("type") == "tool_use":
                    name = block.get("name", "")
                    inp = block.get("input", {})
                    self.tool_uses.append({"name": name, "input": inp})
                    self.current_phase = detect_phase(name, inp)
                    self._track_article(name, inp)
                elif block.get("type") == "text":
                    if not any(b.get("type") == "tool_use" for b in content):
                        self.current_phase = "Thinking..."
            self._update_spinner()

        elif etype == "rate_limit_event":
            info = event.get("rate_limit_info", {})
            if info.get("status") != "allowed":
                self.current_phase = "Rate limited, retrying..."
                self._update_spinner()

        elif etype == "result":
            self.result_event = event

    def _track_article(self, tool_name, tool_input):
        path = tool_input.get("file_path", "")
        if "concepts/" not in path:
            return
        if tool_name == "Write":
            self.articles_created += 1
        elif tool_name == "Edit":
            self.articles_updated += 1

    def _update_spinner(self):
        if not self.show_spinner:
            return
        frame = SPINNER_FRAMES[self.spinner_idx % len(SPINNER_FRAMES)]
        self.spinner_idx += 1
        width = get_terminal_width()
        line = f"{frame} {self.current_phase}"
        if len(line) > width:
            line = line[: width - 1] + "…"
        sys.stderr.write(f"\r\033[K{line}")
        sys.stderr.flush()

    def _clear_spinner(self):
        sys.stderr.write("\r\033[K")
        sys.stderr.flush()

    def finalize(self):
        result = self.result_event or {}
        is_error = result.get("is_error", True)
        subtype = result.get("subtype", "error")
        stop_reason = result.get("stop_reason", "unknown")
        cost = result.get("total_cost_usd", 0)
        duration_ms = result.get("duration_ms", 0)
        num_turns = result.get("num_turns", 0)
        permission_denials = result.get("permission_denials", [])
        result_text = result.get("result", "")

        duration_s = duration_ms / 1000.0 if duration_ms else time.time() - self.start_time

        # Determine success
        success = (
            subtype == "success"
            and not is_error
            and len(permission_denials) == 0
        )

        # Show final spinner state
        if self.show_spinner:
            if success:
                sys.stderr.write(f"\r\033[K✓ Done ({duration_s:.1f}s, ${cost:.2f})\n")
            else:
                reason = stop_reason if stop_reason != "end_turn" else "no useful work"
                sys.stderr.write(f"\r\033[K✗ Failed: {reason}\n")
            sys.stderr.flush()

        # Build summary
        summary = {
            "status": "success" if success else "error",
            "subtype": subtype,
            "is_error": is_error,
            "stop_reason": stop_reason,
            "duration_s": round(duration_s, 1),
            "cost_usd": cost,
            "num_turns": num_turns,
            "articles_created": self.articles_created,
            "articles_updated": self.articles_updated,
            "permission_denials": [
                f"{d.get('tool', '?')}({d.get('command', d.get('reason', '?'))})"
                for d in permission_denials
            ],
            "malformed_lines": self.malformed_lines,
            "log_file": self.log_path,
        }

        if self.json_summary:
            print(json.dumps(summary))
        else:
            self._print_human_summary(summary)

        return 0 if success else 1

    def _print_human_summary(self, summary):
        if summary["status"] == "success":
            print("Compilation complete.")
            articles = []
            if summary["articles_created"] > 0:
                articles.append(f"created {summary['articles_created']}")
            if summary["articles_updated"] > 0:
                articles.append(f"updated {summary['articles_updated']}")
            if articles:
                print(f"  Articles: {', '.join(articles)}")
            print(f"  Duration: {summary['duration_s']}s")
            print(f"  Cost: ${summary['cost_usd']:.2f}")
        else:
            reason = summary["stop_reason"]
            if summary["permission_denials"]:
                reason = "permission denied"
            print(f"Compilation failed: {reason}")
            print(f"  Duration: {summary['duration_s']}s")
            print(f"  Cost: ${summary['cost_usd']:.2f}")
            if summary["permission_denials"]:
                denials_str = ", ".join(summary["permission_denials"])
                print(f"  Blocked tools: {denials_str}")
            print(f"  Details: {summary['log_file']}")


def main():
    parser = argparse.ArgumentParser(description="Claude Code stream-json monitor")
    parser.add_argument("--log", required=True, help="Path to write raw JSONL log")
    parser.add_argument("--json-summary", action="store_true", help="Output summary as JSON (for testing)")
    parser.add_argument("--no-spinner", action="store_true", help="Disable spinner (auto-disabled when stderr is not a TTY)")
    args = parser.parse_args()

    show_spinner = sys.stderr.isatty() and not args.no_spinner

    monitor = StreamMonitor(
        log_path=args.log,
        show_spinner=show_spinner,
        json_summary=args.json_summary,
    )
    exit_code = monitor.run()
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
