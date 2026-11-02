try:
    from mcp.server.mcpserver import MCPServer as FastMCP  # mcp >= 2
except ImportError:
    from mcp.server.fastmcp import FastMCP  # mcp 1.x
import websockets
import json
import sys
import os
import logging
from typing import Dict, Any, Optional, List, Literal, TypedDict, NotRequired

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stderr)]
)
logger = logging.getLogger("MuseScoreMCP")

class MuseScoreClient:
    """Client to communicate with MuseScore WebSocket API."""
    
    def __init__(self, host: str = "localhost", port: int = 8765):
        self.uri = f"ws://{host}:{port}"
        self.websocket = None
    
    async def connect(self):
        """Connect to the MuseScore WebSocket API."""
        try:
            self.websocket = await websockets.connect(self.uri)
            logger.info(f"Connected to MuseScore API at {self.uri}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to MuseScore API: {str(e)}")
            return False
    
    async def send_command(self, action: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Send a command to MuseScore and wait for response."""
        if not self.websocket:
            connected = await self.connect()
            if not connected:
                return {"error": "Not connected to MuseScore"}
        
        if params is None:
            params = {}
        
        command = {"action": action, "params": params}
        
        try:
            logger.info(f"Sending command: {json.dumps(command)}")
            await self.websocket.send(json.dumps(command))
            response = await self.websocket.recv()
            logger.info(f"Received response: {response}")
            return json.loads(response)
        except Exception as e:
            logger.error(f"Error sending command: {str(e)}")
            return {"error": str(e)}
    
    async def close(self):
        """Close the WebSocket connection."""
        if self.websocket:
            await self.websocket.close()
            self.websocket = None
            logger.info("Disconnected from MuseScore API")



# Sounding (concert) MIDI ranges that are comfortably playable, by MuseScore instrument id.
INSTRUMENT_RANGES = {
    "flute": (60, 96), "oboe": (58, 93), "bb-clarinet": (50, 94), "alto-saxophone": (49, 80),
    "bb-trumpet": (52, 82), "trombone": (40, 72), "violins": (55, 100), "violin": (55, 100),
    "viola": (48, 88), "violoncellos": (36, 84), "cello": (36, 84), "contrabass": (28, 67),
    "electric-guitar-tablature": (40, 88), "bass-guitar-tablature": (28, 67), "piano": (21, 108),
}
_NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def _midi_name(m: int) -> str:
    return f"{_NOTE_NAMES[m % 12]}{m // 12 - 1}"


def analyse_arrangement(a: Dict[str, Any]) -> Dict[str, Any]:
    staves = a.get("staves", [])
    measures = a.get("measures", [])
    findings: List[str] = []
    per_staff: List[Dict[str, Any]] = []
    dynamics = 0
    for m in measures:
        for an in m.get("annotations", []) or []:
            if an.get("type") == "Dynamic":
                dynamics += 1
    for si, st in enumerate(staves):
        name = st.get("longName") or f"staff{si}"
        rng = INSTRUMENT_RANGES.get(st.get("instrumentId", ""))
        notes = 0
        out: List[str] = []
        lo, hi = None, None
        measures_with_notes = []
        for m in measures:
            has = False
            for e in m.get("elements", {}).get(f"staff{si}", []):
                if e.get("name") != "Chord":
                    continue
                has = True
                for n in e.get("notes", []):
                    p = n.get("pitchMidi")
                    if p is None:
                        continue
                    notes += 1
                    lo = p if lo is None else min(lo, p)
                    hi = p if hi is None else max(hi, p)
                    if rng and not (rng[0] <= p <= rng[1]):
                        out.append(f"b.{m['measure']} {_midi_name(p)}")
            if has:
                measures_with_notes.append(m["measure"])
        entry: Dict[str, Any] = {"staff": si, "name": name, "notes": notes}
        if notes:
            entry["range"] = f"{_midi_name(lo)}-{_midi_name(hi)}"
            entry["firstMeasure"], entry["lastMeasure"] = measures_with_notes[0], measures_with_notes[-1]
        else:
            findings.append(f"staff {si} ({name}): nothing written")
        if out:
            entry["outOfRange"] = len(out)
            findings.append(f"staff {si} ({name}): {len(out)} note(s) outside {_midi_name(rng[0])}-{_midi_name(rng[1])}, e.g. {', '.join(out[:6])}")
        per_staff.append(entry)
    trailing = []
    for m in reversed(measures):
        if any(e.get("name") == "Chord" for els in m.get("elements", {}).values() for e in els):
            break
        trailing.append(m["measure"])
    if trailing:
        findings.append(f"empty trailing measure(s): {sorted(trailing)[0]}-{sorted(trailing)[-1]}")
    if dynamics == 0:
        findings.append("no dynamics anywhere in the score")
    return {"measures": len(measures), "dynamics": dynamics, "findings": findings, "staves": per_staff}


SNAPSHOT_DIR = os.environ.get("MUSESCORE_SNAPSHOT_DIR", os.path.expanduser("~/Claude_sessions/musescore-snapshots"))


def _score_events(a: Dict[str, Any]) -> Dict[Any, Any]:
    """{(staff, measure): {"events": set of tuples, "marks": set of tuples}} from a get_score analysis."""
    out: Dict[Any, Any] = {}
    for m in a.get("measures", []):
        num = m["measure"]
        for key, els in m.get("elements", {}).items():
            staff = int(key.replace("staff", ""))
            ev = set()
            for e in els:
                if e.get("name") == "Chord":
                    notes = tuple(sorted((n.get("pitchMidi"), n.get("headGroup", 0), bool(n.get("tiedForward"))) for n in e.get("notes", [])))
                    lyr = tuple(l.get("text", "") for l in e.get("lyrics", []))
                    ev.add((e.get("startTick"), e.get("voice", 0), "N", e.get("durationTicks"), notes, lyr))
                elif e.get("name") == "Rest":
                    ev.add((e.get("startTick"), e.get("voice", 0), "R", e.get("durationTicks"), (), ()))
            out.setdefault((staff, num), {"events": set(), "marks": set()})["events"] |= ev
        marks = set()
        for an in m.get("annotations", []) or []:
            marks.add((an.get("staff"), an.get("type"), an.get("text"), an.get("startTick")))
        for cs in m.get("chordSymbols", []) or []:
            marks.add((None, "Chord", cs.get("text"), cs.get("startTick")))
        # marks are per measure, not per staff: keep them under staff -1
        out.setdefault((-1, num), {"events": set(), "marks": set()})["marks"] |= marks
    return out


def _fmt_event(e: tuple) -> str:
    tick, voice, kind, dur, notes, lyr = e
    if kind == "R":
        return f"rest@{tick}"
    pitches = "+".join(f"{_midi_name(p)}{'x' if h else ''}{'~' if t else ''}" for p, h, t in notes)
    return f"{pitches}@{tick}/{dur}" + (f" v{voice + 1}" if voice else "") + (f" '{' '.join(lyr)}'" if any(lyr) else "")


def diff_analyses(old: Dict[str, Any], new: Dict[str, Any], limit: int = 30) -> Dict[str, Any]:
    """Compare two get_score analyses (notes, rests, durations, lyrics, tied/notehead flags, annotations)."""
    names = {i: (s.get("longName") or f"staff{i}") for i, s in enumerate(new.get("staves", []))}
    a, b = _score_events(old), _score_events(new)
    changes: List[Dict[str, Any]] = []
    for key in sorted(set(a) | set(b), key=lambda k: (k[1], k[0])):
        ea = a.get(key, {"events": set(), "marks": set()})
        eb = b.get(key, {"events": set(), "marks": set()})
        removed = sorted(ea["events"] - eb["events"])
        added = sorted(eb["events"] - ea["events"])
        mremoved = sorted(ea["marks"] - eb["marks"], key=str)
        madded = sorted(eb["marks"] - ea["marks"], key=str)
        if removed or added or mremoved or madded:
            staff, meas = key
            changes.append({
                "measure": meas,
                "staff": "(measure marks)" if staff == -1 else f"{staff} {names.get(staff, '?')}",
                "removed": [_fmt_event(e) for e in removed][:6],
                "added": [_fmt_event(e) for e in added][:6],
                "marksRemoved": [list(x) for x in mremoved][:4],
                "marksAdded": [list(x) for x in madded][:4],
            })
    per_staff: Dict[str, int] = {}
    for c in changes:
        per_staff[c["staff"]] = per_staff.get(c["staff"], 0) + 1
    return {
        "measuresBefore": old.get("numMeasures"), "measuresAfter": new.get("numMeasures"),
        "changedStaffMeasures": len(changes), "changesPerStaff": per_staff,
        "identical": not changes, "details": changes[:limit], "truncated": max(0, len(changes) - limit),
    }

class MuseScoreMCP:
    """MCP server providing tools for LLMs to interact with MuseScore."""
    
    def __init__(self, app_name: str = "MuseScore Assistant"):
        self.mcp = FastMCP(app_name)
        self.client = MuseScoreClient()
        
        # Register all the tools based on the JS client functionality
        self.register_tools()
    
    def register_tools(self):
        """Register all tools that map to the JavaScript client functions."""
        
        # Connection & Utility Tools
        @self.mcp.tool()
        async def connect_to_musescore():
            """Connect to the MuseScore WebSocket API."""
            result = await self.client.connect()
            return {"success": result}
        
        @self.mcp.tool()
        async def ping_musescore():
            """Ping the MuseScore WebSocket API to check connection."""
            return await self.client.send_command("ping")
        
        # Score Management Tools
        @self.mcp.tool()
        async def get_score(
            staves: Optional[List[int]] = None,
            start_measure: Optional[int] = None,
            end_measure: Optional[int] = None,
            summary: bool = False,
        ):
            """Get information about the current score.

            A full dump of a large score is ~2 MB. Use `summary=True` for a per-staff overview
            (note counts, measure runs with notes), or filter with `staves` (0-based staff
            indexes) and `start_measure`/`end_measure` (1-based, inclusive).
            """
            params: Dict[str, Any] = {}
            if staves is not None:
                params["staves"] = staves
            if start_measure is not None:
                params["startMeasure"] = start_measure
            if end_measure is not None:
                params["endMeasure"] = end_measure
            if summary:
                params["summary"] = True
            return await self.client.send_command("getScore", params)
        
        @self.mcp.tool()
        async def snapshot_score(label: str):
            """Save the current score's notes/lyrics/annotations under a label, to compare against later
            with diff_score. Take one BEFORE a risky batch of edits."""
            import re as _re
            if not _re.fullmatch(r"[A-Za-z0-9_-]{1,40}", label):
                return {"error": "label must be 1-40 characters: letters, digits, _ or -"}
            resp = await self.client.send_command("getScore", {})
            res = resp.get("result", resp) if isinstance(resp, dict) else {}
            analysis = res.get("analysis") if isinstance(res, dict) else None
            if not analysis or "measures" not in analysis:
                return {"error": "could not read the score"}
            os.makedirs(SNAPSHOT_DIR, exist_ok=True)
            path = os.path.join(SNAPSHOT_DIR, f"{label}.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(analysis, f)
            return {"saved": path, "measures": analysis.get("numMeasures"), "staves": len(analysis.get("staves", []))}

        @self.mcp.tool()
        async def diff_score(label: str, limit: int = 30):
            """Compare the current score with a snapshot taken by snapshot_score and list what changed
            (notes, rests, durations, lyrics, ties, noteheads, annotations), per staff and measure."""
            import re as _re
            if not _re.fullmatch(r"[A-Za-z0-9_-]{1,40}", label):
                return {"error": "label must be 1-40 characters: letters, digits, _ or -"}
            path = os.path.join(SNAPSHOT_DIR, f"{label}.json")
            if not os.path.exists(path):
                return {"error": f"no snapshot '{label}'", "available": sorted(x[:-5] for x in os.listdir(SNAPSHOT_DIR)) if os.path.isdir(SNAPSHOT_DIR) else []}
            with open(path, encoding="utf-8") as f:
                old = json.load(f)
            resp = await self.client.send_command("getScore", {})
            res = resp.get("result", resp) if isinstance(resp, dict) else {}
            analysis = res.get("analysis") if isinstance(res, dict) else None
            if not analysis or "measures" not in analysis:
                return {"error": "could not read the score"}
            return diff_analyses(old, analysis, limit)

        @self.mcp.tool()
        async def check_arrangement():
            """Read-only sanity check of the open score: notes outside each instrument's playable
            range, empty trailing measures, staves with nothing written, missing dynamics."""
            resp = await self.client.send_command("getScore", {})
            res = resp.get("result", resp) if isinstance(resp, dict) else {}
            analysis = res.get("analysis") if isinstance(res, dict) else None
            if not analysis or "measures" not in analysis:
                return {"error": "could not read the score", "response": str(resp)[:300]}
            return analyse_arrangement(analysis)

        # Cursor & Navigation Tools
        @self.mcp.tool()
        async def get_cursor_info():
            """Get information about the current cursor position."""
            return await self.client.send_command("getCursorInfo")
        
        # @self.mcp.tool()
        # async def go_to_measure(measure: int):
        #     """Navigate to a specific measure."""
        #     return await self.client.send_command("goToMeasure", {"measure": measure})
        
        # @self.mcp.tool()
        # async def go_to_final_measure():
        #     """Navigate to the final measure of the score."""
        #     return await self.client.send_command("goToFinalMeasure")
        
        # @self.mcp.tool()
        # async def go_to_beginning_of_score():
        #     """Navigate to the beginning of the score."""
        #     return await self.client.send_command("goToBeginningOfScore")
        
        # @self.mcp.tool()
        # async def next_element():
        #     """Move cursor to the next element."""
        #     return await self.client.send_command("nextElement")
        
        # @self.mcp.tool()
        # async def prev_element():
        #     """Move cursor to the previous element."""
        #     return await self.client.send_command("prevElement")
        
        # @self.mcp.tool()
        # async def select_current_measure():
        #     """Select the current measure."""
        #     return await self.client.send_command("selectCurrentMeasure")
        
        # # Notes & Measures Tools
        # @self.mcp.tool()
        # async def add_note(pitch: int = 64, duration: object = {"numerator": 1, "denominator": 4}):
        #     """Add a note at the current cursor position with the specified pitch and duration."""
        #     return await self.client.send_command("addNote", {"pitch": pitch, "duration": duration})
        
        # @self.mcp.tool()
        # async def add_rest(duration: object = {"numerator": 1, "denominator": 4}):
        #     """Add a rest at the current cursor position."""
        #     return await self.client.send_command("addRest", {"duration": duration})
        
        # @self.mcp.tool()
        # async def add_tuplet(duration: object = {"numerator": 1, "denominator": 4}, ratio: object = {"numerator": 3, "denominator": 2}):
        #     """Add a tuplet at the current cursor position."""
        #     return await self.client.send_command("addTuplet", {
        #         "ratio": {"duration": duration, "ratio": ratio}
        #     })
        
        # @self.mcp.tool()
        # async def insert_measure():
        #     """Insert a measure at the current position."""
        #     return await self.client.send_command("insertMeasure")
        
        # @self.mcp.tool()
        # async def append_measure(count: int = 1):
        #     """Append measures to the end of the score."""
        #     return await self.client.send_command("appendMeasure", {"count": count})
        
        # @self.mcp.tool()
        # async def delete_selection(measure: Optional[int] = None):
        #     """Delete the current selection or specified measure."""
        #     params = {}
        #     if measure is not None:
        #         params["measure"] = measure
        #     return await self.client.send_command("deleteSelection", params)
        
        # # Time & Tempo Tools
        # @self.mcp.tool()
        # async def set_time_signature(numerator: int = 4, denominator: int = 4):
        #     """Set the time signature."""
        #     return await self.client.send_command("setTimeSignature", {
        #         "numerator": numerator,
        #         "denominator": denominator
        #     })


        class getScoreAction(TypedDict):
            action: Literal["getScore"]
            params: Dict[str, Any]

        class addNoteParams(TypedDict):
            pitch: int
            duration: Dict[Literal["numerator", "denominator"], int]
            advanceCursorAfterAction: bool
            # Optional explicit tablature placement (guitar/bass tab staves).
            # string: 0 = highest-pitched string, increasing downward (e.g. standard 6-string guitar: 0=high e ... 5=low E).
            # fret: fret number on that string. When both are given, overrides MuseScore's automatic
            # string/fret assignment so chords come out in a physically playable position.
            string: NotRequired[int]
            fret: NotRequired[int]
            # Explicit override for whether this note stacks onto the chord already at the
            # cursor position (True) or replaces it as a fresh single note (False). When omitted,
            # it's auto-detected: replaces a Rest, stacks onto an existing Chord.
            addToChord: NotRequired[bool]
            voice: NotRequired[int]  # 0-3; overrides the currently active voice for this call only

        class addNoteAction(TypedDict):
            action: Literal["addNote"]
            params: addNoteParams

        class addRestParams(TypedDict):
            duration: Dict[Literal["numerator", "denominator"], int]
            advanceCursorAfterAction: bool
            voice: NotRequired[int]  # 0-3; overrides the currently active voice for this call only

        class addRestAction(TypedDict):
            action: Literal["addRest"]
            params: addRestParams

        class addTupletParams(TypedDict):
            duration: Dict[Literal["numerator", "denominator"], int]
            ratio: Dict[Literal["numerator", "denominator"], int]
            advanceCursorAfterAction: bool

        class addTupletAction(TypedDict):
            action: Literal["addTuplet"]
            params: addTupletParams

        class appendMeasureAction(TypedDict):
            action: Literal["appendMeasure"]
            params: Dict[str, Any]

        class deleteSelectionAction(TypedDict):
            action: Literal["deleteSelection"]
            params: Dict[str, Any]

        class getCursorInfoAction(TypedDict):
            action: Literal["getCursorInfo"]
            params: Dict[str, Any]

        class goToMeasureParams(TypedDict):
            measure: int
            voice: NotRequired[int]  # 0-3; switches the active voice for this and subsequent actions (default: stays on the current voice)

        class goToMeasureAction(TypedDict):
            action: Literal["goToMeasure"]
            params: goToMeasureParams

        class nextElementAction(TypedDict):
            action: Literal["nextElement"]
            params: Dict[str, Any]

        class prevElementAction(TypedDict):
            action: Literal["prevElement"]
            params: Dict[str, Any]

        class selectCurrentMeasureAction(TypedDict):
            action: Literal["selectCurrentMeasure"]
            params: Dict[str, Any]

        class insertMeasureAction(TypedDict):
            action: Literal["insertMeasure"]
            params: Dict[str, Any]

        class goToFinalMeasureAction(TypedDict):
            action: Literal["goToFinalMeasure"]
            params: Dict[str, Any]

        class goToBeginningOfScoreAction(TypedDict):
            action: Literal["goToBeginningOfScore"]
            params: Dict[str, Any]

        class setTimeSignatureParams(TypedDict):
            numerator: int
            denominator: int

        class setTimeSignatureAction(TypedDict):
            action: Literal["setTimeSignature"]
            params: setTimeSignatureParams

        class undoAction(TypedDict):
            # Not supported: the plugin returns an error (cmd("undo") has no effect from a plugin); use Cmd+Z in MuseScore.
            action: Literal["undo"]
            params: Dict[str, Any]

        class nextStaffAction(TypedDict):
            action: Literal["nextStaff"]
            params: Dict[str, Any]

        class prevStaffAction(TypedDict):
            action: Literal["prevStaff"]
            params: Dict[str, Any]

        class stringFretAssignment(TypedDict):
            string: int  # 0 = highest-pitched string, increasing downward (standard 6-string guitar: 0=high e ... 5=low E)
            fret: int

        class setStringFretParams(TypedDict):
            # Must be given in the SAME order the chord's notes were added (addNote calls).
            # Run this as its own action right after a chord's notes are all in place (and, if the
            # chord isn't the measure's last, before advancing) — it overrides MuseScore's automatic
            # tab string/fret choice, which can otherwise land far apart on the neck (unplayable).
            assignments: List[stringFretAssignment]

        class setStringFretAction(TypedDict):
            action: Literal["setStringFret"]
            params: setStringFretParams

        class selectCustomRangeParams(TypedDict):
            startTick: int
            endTick: int
            startStaff: int
            endStaff: int  # exclusive, like Python range() — e.g. 0..1 selects only staff 0

        class selectCustomRangeAction(TypedDict):
            action: Literal["selectCustomRange"]
            params: selectCustomRangeParams

        class addLyricsParams(TypedDict):
            lyrics: List[str]  # one syllable/word per Chord starting at the cursor; Rests are skipped, not consumed
            verse: NotRequired[int]  # which lyric line to write to (default 0, the first verse)

        class addLyricsAction(TypedDict):
            action: Literal["addLyrics"]
            params: addLyricsParams

        class spellingAssignment(TypedDict):
            tpc: int  # tonal pitch class, e.g. 7=Cb, 9=Db, 11=Eb, 13=F, 8=Gb, 10=Ab, 12=Bb, 14=C (TPC 14 = C, +1 per fifth up)

        class setNoteSpellingParams(TypedDict):
            # Must be given in the SAME order the chord's notes were added. Run as its own action
            # right after a chord's notes are all in place — forces the notated spelling (flat vs
            # sharp) instead of whatever enharmonic MuseScore's addNote defaulted to.
            assignments: List[spellingAssignment]

        class setNoteSpellingAction(TypedDict):
            action: Literal["setNoteSpelling"]
            params: setNoteSpellingParams

        class setNoteHeadsParams(TypedDict):
            staff: int  # 0-based staff index
            startTick: int  # inclusive
            endTick: int  # exclusive
            head: Literal["cross", "normal"]  # "cross" = x noteheads (spoken passages)

        class setNoteHeadsAction(TypedDict):
            action: Literal["setNoteHeads"]
            params: setNoteHeadsParams

        class addDynamicParams(TypedDict):
            staff: int
            tick: int
            dynamic: str  # e.g. "p", "mf", "ff", "sfz"

        class addDynamicAction(TypedDict):
            action: Literal["addDynamic"]
            params: addDynamicParams

        class tickRangeParams(TypedDict):
            staff: int  # 0-based
            startTick: int  # inclusive
            endTick: int  # exclusive

        class addHairpinParams(TypedDict):
            staff: int
            startTick: int
            endTick: int
            type: Literal["crescendo", "diminuendo"]

        class addHairpinAction(TypedDict):
            action: Literal["addHairpin"]
            params: addHairpinParams

        class addArticulationParams(TypedDict):
            staff: int
            startTick: int
            endTick: int
            articulation: Literal["staccato", "staccatissimo", "accent", "tenuto", "marcato", "tenuto-staccato"]

        class addArticulationAction(TypedDict):
            action: Literal["addArticulation"]
            params: addArticulationParams

        class addTextParams(TypedDict):
            staff: int
            tick: int
            kind: Literal["staff", "system", "rehearsal", "tempo"]
            text: str

        class addTextAction(TypedDict):
            action: Literal["addText"]
            params: addTextParams

        class addSlurAction(TypedDict):
            action: Literal["addSlur"]
            params: tickRangeParams

        class addTieAction(TypedDict):
            action: Literal["addTie"]
            params: tickRangeParams

        class moveToVoiceParams(TypedDict):
            staff: int
            startTick: int
            endTick: int
            voice: int  # 0-3

        class moveToVoiceAction(TypedDict):
            action: Literal["moveToVoice"]
            params: moveToVoiceParams

        class deleteMeasuresParams(TypedDict):
            startMeasure: int  # 1-based, inclusive
            endMeasure: int

        class deleteMeasuresAction(TypedDict):
            action: Literal["deleteMeasures"]
            params: deleteMeasuresParams

        class setPartVisibleParams(TypedDict):
            staff: int  # any staff of the instrument
            visible: bool

        class setPartVisibleAction(TypedDict):
            action: Literal["setPartVisible"]
            params: setPartVisibleParams

        class setStyleParams(TypedDict):
            name: str  # MuseScore style name, e.g. "hideEmptyStaves"
            value: bool | int | float | str

        class setStyleAction(TypedDict):
            action: Literal["setStyle"]
            params: setStyleParams

        class addChordSymbolParams(TypedDict):
            staff: int
            tick: int
            text: str  # e.g. "Am7", "C/E"

        class addChordSymbolAction(TypedDict):
            action: Literal["addChordSymbol"]
            params: addChordSymbolParams

        class copyMeasuresParams(TypedDict):
            startMeasure: int  # 1-based, inclusive
            endMeasure: int
            destMeasure: int  # first destination measure; existing content there is overwritten
            firstStaff: NotRequired[int]  # default: all staves
            lastStaff: NotRequired[int]

        class copyMeasuresAction(TypedDict):
            action: Literal["copyMeasures"]
            params: copyMeasuresParams

        class transposeParams(TypedDict):
            staff: int
            startTick: int
            endTick: int
            semitones: int  # -24..24

        class transposeAction(TypedDict):
            action: Literal["transpose"]
            params: transposeParams

        class introspectParams(TypedDict):
            names: NotRequired[List[str]]  # enums to list: Element, ClefType, BarLineType, Segment
            scoreProps: NotRequired[List[str]]  # Score property names whose values to read, e.g. ["title", "composer"]
            selectAll: NotRequired[bool]  # list the text elements found by "select all"
            objects: NotRequired[List[Dict[str, Any]]]  # e.g. [{"type": "barline", "measure": 2}, {"type": "part", "staff": 1}]

        class introspectAction(TypedDict):
            action: Literal["introspect"]
            params: introspectParams

        class setBarlineParams(TypedDict):
            measure: int  # 1-based
            type: Literal["normal", "double", "final", "repeat-end", "repeat-start"]

        class setBarlineAction(TypedDict):
            action: Literal["setBarline"]
            params: setBarlineParams

        class addClefParams(TypedDict):
            staff: int
            tick: int
            clef: Literal["treble", "bass", "alto", "tenor", "treble8vb", "percussion"]

        class addClefAction(TypedDict):
            action: Literal["addClef"]
            params: addClefParams

        class exportScoreParams(TypedDict):
            path: str  # absolute path WITHOUT extension
            format: Literal["pdf", "mid", "musicxml", "mxl", "png", "wav", "mp3", "flac", "ogg"]

        class exportScoreAction(TypedDict):
            action: Literal["exportScore"]
            params: exportScoreParams

        class exportPartsParams(TypedDict):
            directory: str  # absolute path
            format: Literal["pdf", "mid", "musicxml", "mxl", "png", "wav", "mp3", "flac", "ogg"]

        class exportPartsAction(TypedDict):
            action: Literal["exportParts"]
            params: exportPartsParams

        class saveScoreAction(TypedDict):
            action: Literal["saveScore"]
            params: Dict[str, Any]

        class removePartParams(TypedDict):
            staff: int  # any staff of the part; the WHOLE part (all its staves) is removed
            partName: str  # must equal the part's long name, e.g. "Piano"

        class removePartAction(TypedDict):
            action: Literal["removePart"]
            params: removePartParams

        class setScoreTextParams(TypedDict):
            kind: Literal["title", "subtitle", "composer", "lyricist", "parttitle"]
            text: str

        class setScoreTextAction(TypedDict):
            action: Literal["setScoreText"]
            params: setScoreTextParams

        class addMarkerParams(TypedDict):
            measure: int  # 1-based
            kind: Literal["segno", "coda", "tocoda", "fine"]

        class addMarkerAction(TypedDict):
            action: Literal["addMarker"]
            params: addMarkerParams

        class addJumpParams(TypedDict):
            measure: int  # 1-based
            kind: Literal["dc", "dc-al-fine", "dc-al-coda", "ds", "ds-al-fine", "ds-al-coda"]

        class addJumpAction(TypedDict):
            action: Literal["addJump"]
            params: addJumpParams

        class setTitleParams(TypedDict):
            title: str

        class setTitleAction(TypedDict):
            action: Literal["setTitle"]
            params: setTitleParams

        class setTempoParams(TypedDict):
            bpm: int

        class setTempoAction(TypedDict):
            action: Literal["setTempo"]
            params: setTempoParams

        class addInstrumentParams(TypedDict):
            instrumentId: str  # MuseScore instrument id, e.g. "flute", "acoustic-guitar-nylon"

        class addInstrumentAction(TypedDict):
            action: Literal["addInstrument"]
            params: addInstrumentParams

        class setVoiceParams(TypedDict):
            voice: int  # 0-3. Switches which voice subsequent actions on this staff read/write, until changed again or the staff changes.

        class setVoiceAction(TypedDict):
            action: Literal["setVoice"]
            params: setVoiceParams

        type ActionSequence = List[getScoreAction | addNoteAction | addRestAction | addTupletAction | appendMeasureAction | deleteSelectionAction | getCursorInfoAction | goToMeasureAction | nextElementAction | prevElementAction | selectCurrentMeasureAction | insertMeasureAction | goToFinalMeasureAction | goToBeginningOfScoreAction | setTimeSignatureAction | undoAction | nextStaffAction | prevStaffAction | setStringFretAction | selectCustomRangeAction | addLyricsAction | setNoteSpellingAction | setNoteHeadsAction | addDynamicAction | addHairpinAction | addArticulationAction | addTextAction | addSlurAction | addTieAction | moveToVoiceAction | setPartVisibleAction | setStyleAction | addChordSymbolAction | copyMeasuresAction | transposeAction | introspectAction | removePartAction | addMarkerAction | addJumpAction | setScoreTextAction | setBarlineAction | addClefAction | exportScoreAction | exportPartsAction | saveScoreAction | deleteMeasuresAction | setTitleAction | setTempoAction | addInstrumentAction | setVoiceAction]

        @self.mcp.tool()
        async def processSequence(sequence: ActionSequence):
            """Process a sequence of commands."""
            return await self.client.send_command("processSequence", {"sequence": sequence})
    
    def run(self):
        """Run the MCP server."""
        sys.stderr.write("MuseScore MCP Server starting up...\n")
        sys.stderr.flush()
        logger.info("MuseScore MCP Server is running")
        self.mcp.run()


# Main entry point
if __name__ == "__main__":
    # Create and run the server
    server = MuseScoreMCP("MuseScore Assistant")
    server.run()
