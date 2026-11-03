import QtQuick 2.9
import MuseScore 3.0

MuseScore {
    id: root
    menuPath: "Plugins.MuseScore API Server"
    description: "Exposes MuseScore API via WebSocket"
    version: "1.0"
    
    property var clientConnections: []
    
    // Global state to track selection position
    property var selectionState: ({
        startStaff: 0,
        endStaff: 1,
        startTick: 0,
        elements: [],
        voice: 0
    });

    function processMessage(message, clientId) {
        console.log("Received message: " + message);
        try {
            var command = JSON.parse(message);
            var result = processCommand(command);
            api.websocketserver.send(clientId, JSON.stringify({
                status: "success",
                result: result
            }));
        } catch (e) {
            console.log("Error processing command: " + e.toString());
            api.websocketserver.send(clientId, JSON.stringify({
                status: "error",
                message: e.toString()
            }));
        }
    }

    // Multi-action commands

    function processSequence(params) {
        if (!curScore) return { error: "No score open" };

        if (!params.sequence) {
            return { error: "No sequence specified" };
        }

        var validCommands = [
            "getScore",
            "addNote",
            "addRest",
            "addTuplet",
            "appendMeasure",
            "deleteSelection",
            "getCursorInfo",
            "goToMeasure",
            "nextElement",
            "prevElement",
            "nextStaff",
            "prevStaff",
            "selectCurrentMeasure",
            "processSequence",
            "insertMeasure",
            "goToFinalMeasure",
            "goToBeginningOfScore",
            "setTimeSignature",
            "undo",
            "debugApi",
            "setStringFret",
            "selectCustomRange",
            "addLyrics",
            "setNoteSpelling",
            "setNoteHeads",
            "addDynamic",
            "addHairpin",
            "addArticulation",
            "addText",
            "addSlur",
            "addTie",
            "moveToVoice",
            "introspect",
            "removePart",
            "addMarker",
            "addJump",
            "setScoreText",
            "setBarline",
            "addClef",
            "exportScore",
            "exportParts",
            "saveScore",
            "setPartVisible",
            "setStyle",
            "addChordSymbol",
            "copyMeasures",
            "setNotePitches",
            "transpose",
            "deleteMeasures",
            "setTitle",
            "setTempo",
            "addInstrument",
            "setVoice"
        ]

        var collectedInfo = [];
        var collectedMessages = [];
        try {
            // process commands in order
            for (var i = 0; i < params.sequence.length; i++) {
                if (!validCommands.includes(params.sequence[i].action)) {
                    throw new Error("Invalid command: " + params.sequence[i].action + " Valid commands: " + validCommands.join(", "));
                }
                // Individual action functions catch their own exceptions and return
                // { error: ... } instead of throwing - surface that immediately instead of
                // silently continuing the sequence with whatever state the failed action left.
                var actionResult = processCommand(params.sequence[i]);
                if (actionResult && actionResult.error) {
                    throw new Error("Action " + (i + 1) + " (" + params.sequence[i].action + ") failed: " + actionResult.error);
                }
                if (actionResult && actionResult.message && actionResult.success) collectedMessages.push(params.sequence[i].action + ": " + actionResult.message);
                // Actions that return data for the caller (e.g. introspect) put it in `info`.
                if (actionResult && actionResult.info !== undefined) {
                    collectedInfo.push({ action: params.sequence[i].action, info: actionResult.info });
                }
            }

            // Full per-measure data is ~2 MB on a real score; callers verify with get_score
            // (which now supports staff/measure filters and a summary mode) instead.
            var finalSummary = getScoreSummary();
            var response = { success: true, message: "Sequence processed", currentSelection: selectionState,
                     currentScore: { numMeasures: finalSummary.numMeasures, staves: finalSummary.staves } };
            if (collectedInfo.length) response.info = collectedInfo;
            response.messages = collectedMessages;
            return response;
        } catch (e) {
            return { error: e.toString() };
        }
    }
    
    function processCommand(command) {
        console.log("Processing command: " + command.action);
        switch(command.action) {
            // Basic score operations
            case "getScore":
                return getScore(command.params);
            case "syncStateToSelection":
                return syncStateToSelection();
                
            // Sequence
            case "processSequence":
                return processSequence(command.params);

            // Note and measure operations
            case "addNote":
                return addNote(command.params);
            case "addRest":
                return addRest(command.params);
            case "addTuplet":
                return addTuplet(command.params);
            case "appendMeasure":
                return appendMeasure(command.params);
            case "deleteSelection":
                return deleteSelection(command.params);
                
            // Cursor and navigation
            case "getCursorInfo":
                return getCursorInfo(command.params);
            case "goToMeasure":
                return goToMeasure(command.params);
            case "nextElement":
                return nextElement(command.params);
            case "prevElement":
                return prevElement(command.params);
            case "nextStaff":
                return nextStaff(command.params);
            case "prevStaff":
                return prevStaff(command.params);
            case "setVoice":
                return setVoice(command.params);
            case "selectCurrentMeasure":
                return selectCurrentMeasure(command.params);
            case "selectCustomRange":
                return selectCustomRange(command.params);
            case "insertMeasure":
                return insertMeasure(command.params);
            case "goToFinalMeasure":
                return goToFinalMeasure(command.params);
                
            // Staff and instrument operations
            case "addInstrument":
                return addInstrument(command.params);
            case "setStaffMute":
                return setStaffMute(command.params);
            case "setInstrumentSound":
                return setInstrumentSound(command.params);
                
            // Time signature and tempo
            case "setTimeSignature":
                return setTimeSignature(command.params);
            case "setTempo":
                return setTempo(command.params);
            case "setTitle":
                return setTitle(command.params);
                
                
            // Utility
            case "undo":
                return undo(command.params);
            case "setStringFret":
                return setStringFret(command.params);
            case "addDynamic":
                return addDynamic(command.params);
            case "addHairpin":
                return addHairpin(command.params);
            case "addArticulation":
                return addArticulation(command.params);
            case "addText":
                return addText(command.params);
            case "addSlur":
                return addSlur(command.params);
            case "addTie":
                return addTie(command.params);
            case "setPartVisible":
                return setPartVisible(command.params);
            case "setStyle":
                return setStyle(command.params);
            case "addChordSymbol":
                return addChordSymbol(command.params);
            case "copyMeasures":
                return copyMeasures(command.params);
            case "setNotePitches":
                return setNotePitches(command.params);
            case "transpose":
                return transpose(command.params);
            case "setScoreText":
                return setScoreText(command.params);
            case "addMarker":
                return addMarker(command.params);
            case "addJump":
                return addJump(command.params);
            case "introspect":
                return introspect(command.params);
            case "setBarline":
                return setBarline(command.params);
            case "addClef":
                return addClef(command.params);
            case "exportScore":
                return exportScore(command.params);
            case "exportParts":
                return exportParts(command.params);
            case "saveScore":
                return saveScore(command.params);
            case "moveToVoice":
                return moveToVoice(command.params);
            case "deleteMeasures":
                return deleteMeasures(command.params);
            case "removePart":
                return removePart(command.params);
            case "setNoteHeads":
                return setNoteHeads(command.params);
            case "setNoteSpelling":
                return setNoteSpelling(command.params);
            case "addLyrics":
                return addLyrics(command.params);
            case "setKeySignature":
                return setKeySignature(command.params);
            case "ping":
                return "pong";
            case "debugApi":
                return {
                    apiKeys: Object.keys(api),
                    wsKeys: api.websocketserver ? Object.keys(api.websocketserver) : null,
                    wsProtoKeys: api.websocketserver ? Object.keys(Object.getPrototypeOf(api.websocketserver) || {}) : null,
                    hasClose: api.websocketserver ? (typeof api.websocketserver.close) : "n/a",
                    hasStop: api.websocketserver ? (typeof api.websocketserver.stop) : "n/a",
                    hasIsListening: api.websocketserver ? (typeof api.websocketserver.isListening) : "n/a",
                    hasListening: api.websocketserver ? (typeof api.websocketserver.listening) : "n/a"
                };
            case "goToBeginningOfScore":
                var response = initCursorState();
                return { 
                    success: true, 
                    message: response, 
                    currentSelection: selectionState,
                    currentScore: getScoreSummary()
                };
            default:
                throw new Error("Unknown command: " + command.action);
        }
    }
    
    // Score Management

    // Key signature

    // Set the key signature at the start of a given measure, across all staves.
    // params.key: number of sharps (positive) or flats (negative), -7..7, 0 = C major/A minor.
    //
    // KNOWN LIMITATION: this returns success and doesn't throw, but inserting a new
    // KeySig via newElement(Element.KEYSIG) + cursor.add() does not reliably produce
    // a visible key signature change in MuseScore 4 - a documented gap in the plugin
    // API (see e.g. https://musescore.org/en/node/330288). Left in for reference /
    // in case a future MuseScore build fixes it; verify visually before trusting it.
    function setKeySignature(params) {
        if (!curScore) return { error: "No score open" };
        if (params.measure === undefined || params.key === undefined) {
            return { error: "measure and key must be specified. key is sharps(+)/flats(-), -7..7." };
        }

        // must run before our own startCmd below - see goToMeasure for why nesting corrupts it
        var score = getScoreSummary();
        var measure = score.measures[params.measure - 1];
        if (!measure) return { error: "Measure " + params.measure + " not found" };
        var startTick = measure.startTick;

        curScore.startCmd();
        try {
            for (var s = 0; s < curScore.nstaves; s++) {
                var cursor = curScore.newCursor();
                cursor.staffIdx = s;
                cursor.rewindToTick(startTick);
                var ks = newElement(Element.KEYSIG);
                ks.key = params.key;
                cursor.add(ks);
            }

            curScore.endCmd();
            return { success: true, message: "Key signature set to " + params.key + " at measure " + params.measure };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Undo

    function undo(params) {
        if (!curScore) return { error: "No score open" };

        // cmd("undo") from a plugin does nothing in MuseScore 4, neither inside nor outside
        // startCmd()/endCmd() and for notes as well as annotations (verified by reading the score
        // back), while Cmd+Z in the GUI works. Report that instead of claiming success.
        return { error: "undo is not supported from the plugin (cmd('undo') has no effect); use Cmd+Z in MuseScore" };
    }
    
    // Explicitly assign string/fret to the notes of the chord at the current cursor position
    // (tablature staves). params.assignments is an array of {string, fret}, applied in order to
    // the chord's notes array (index i of assignments -> index i of notes), so it must be given
    // in the SAME order the notes were added. Run this as its own action AFTER a chord's notes
    // have all been added (and, if there is one, before advancing to the next position) — doing
    // it in a separate command/undo step avoids MuseScore's own automatic string/fret assignment
    // reshuffling notes mid-chord-build, which addNote's inline attempt could not fully avoid.
    function setStringFret(params) {
        if (!curScore) return { error: "No score open" };
        if (!params.assignments || !params.assignments.length) {
            return { error: "assignments must be a non-empty array of { string, fret }" };
        }

        curScore.startCmd();
        try {
            syncStateToSelection();
            var cursor = createCursor();
            var element = cursor.element;

            if (!element || !element.notes || element.notes.length === 0) {
                curScore.endCmd(true);
                return { error: "No chord found at the current cursor position" };
            }

            var notesArr = element.notes;
            var n = Math.min(params.assignments.length, notesArr.length);
            for (var i = 0; i < n; i++) {
                notesArr[i].string = params.assignments[i].string;
                notesArr[i].fret = params.assignments[i].fret;
            }

            var processedElement = processElement(cursor.element);
            curScore.endCmd();
            return {
                success: true,
                message: "String/fret assignments applied to " + n + " note(s)",
                currentSelection: { startStaff: cursor.staffIdx, endStaff: cursor.staffIdx, startTick: cursor.tick, elements: [processedElement], totalDuration: processedElement.durationTicks },
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Change the notehead shape of every note on one staff (voice 0) between startTick
    // (inclusive) and endTick (exclusive). params.head: "cross" (x, e.g. spoken passages) or
    // "normal". Pitch/playback data is untouched - only the drawn notehead changes.
    function setNoteHeads(params) {
        if (!curScore) return { error: "No score open" };
        if (params.staff === undefined || params.startTick === undefined || params.endTick === undefined) {
            return { error: "staff (0-based), startTick, endTick and head (\"cross\"|\"normal\") must be specified" };
        }
        if (params.head !== "cross" && params.head !== "normal") {
            return { error: "head must be \"cross\" or \"normal\"" };
        }

        curScore.startCmd();
        try {
            // The enum is exposed as NoteHead.Group.X, NoteHead.X or not at all depending on the
            // build; fall back to the underlying numeric values (HEAD_NORMAL=0, HEAD_CROSS=1).
            var want = params.head === "cross" ? "HEAD_CROSS" : "HEAD_NORMAL";
            var group = params.head === "cross" ? 1 : 0;
            var enumSource = "numeric fallback";
            if (typeof NoteHead !== "undefined") {
                if (NoteHead.Group && NoteHead.Group[want] !== undefined) { group = NoteHead.Group[want]; enumSource = "NoteHead.Group"; }
                else if (NoteHead[want] !== undefined) { group = NoteHead[want]; enumSource = "NoteHead"; }
            }

            // Plain cursor on purpose: createCursor() syncs with the live input voice.
            var cursor = curScore.newCursor();
            cursor.staffIdx = params.staff;
            cursor.voice = 0;
            cursor.rewindToTick(params.startTick);

            var chords = 0, notes = 0;
            while (cursor.segment && cursor.tick < params.endTick) {
                var el = cursor.element;
                if (el && el.type === Element.CHORD) {
                    chords++;
                    for (var i = 0; i < el.notes.length; i++) {
                        el.notes[i].headGroup = group;
                        notes++;
                    }
                }
                if (!cursor.next()) break;
            }

            curScore.endCmd();
            return { success: true, message: "Notehead '" + params.head + "' (" + group + ", via " + enumSource + ") set on " + notes + " note(s) in " + chords + " chord(s)" };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Explicitly assign notation spelling (TPC - tonal pitch class, e.g. Cb vs B for the same
    // sounding pitch) to the notes of the chord at the current cursor position. Same pattern as
    // setStringFret: params.assignments is an array of { tpc }, applied in order to the chord's
    // notes array, run as its own action AFTER the chord's notes are all added. Use this to force
    // a flat spelling (or sharp) matching the surrounding key signature/context instead of
    // whatever enharmonic MuseScore's addNote defaults to for a chromatic pitch.
    function setNoteSpelling(params) {
        if (!curScore) return { error: "No score open" };
        if (!params.assignments || !params.assignments.length) {
            return { error: "assignments must be a non-empty array of { tpc }" };
        }

        curScore.startCmd();
        try {
            syncStateToSelection();
            var cursor = createCursor();
            var element = cursor.element;

            if (!element || !element.notes || element.notes.length === 0) {
                curScore.endCmd(true);
                return { error: "No chord found at the current cursor position" };
            }

            var notesArr = element.notes;
            var n = Math.min(params.assignments.length, notesArr.length);
            for (var i = 0; i < n; i++) {
                var tpc = params.assignments[i].tpc;
                notesArr[i].tpc1 = tpc;
                notesArr[i].tpc2 = tpc;
            }

            var processedElement = processElement(cursor.element);
            curScore.endCmd();
            return {
                success: true,
                message: "Spelling assignments applied to " + n + " note(s)",
                currentSelection: { startStaff: cursor.staffIdx, endStaff: cursor.staffIdx, startTick: cursor.tick, elements: [processedElement], totalDuration: processedElement.durationTicks },
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Attach lyric syllables to consecutive notes starting at the current cursor position.
    // Consumes params.lyrics (an array of strings) one per Chord encountered, skipping Rests,
    // advancing the cursor after each one, until the array is exhausted or the score ends.
    // params.verse (default 0) selects which lyric line/verse to write to.
    function addLyrics(params) {
        if (!curScore) return { error: "No score open" };
        if (!params.lyrics || !Array.isArray(params.lyrics) || params.lyrics.length === 0) {
            return { error: "Lyrics must be specified as a non-empty array of strings" };
        }

        curScore.startCmd();
        try {
            syncStateToSelection();
            var cursor = createCursor({ startTick: selectionState.startTick, startStaff: selectionState.startStaff });

            var lyricsArray = params.lyrics.slice();
            var verse = params.verse || 0;
            var addedCount = 0;
            var skippedCount = 0;

            while (cursor.element && lyricsArray.length > 0) {
                var element = cursor.element;

                if (element.name === "Chord") {
                    var lyr = newElement(Element.LYRICS);
                    lyr.text = lyricsArray.shift();
                    lyr.verse = verse;
                    cursor.add(lyr);
                    addedCount++;
                } else if (element.name === "Rest") {
                    skippedCount++;
                }

                if (!cursor.next()) break;
            }

            var processedElement = processElement(cursor.element);
            var startTick = cursor.tick;
            var staffIdx = cursor.staffIdx;

            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx,
                startTick: startTick,
                elements: [processedElement],
                totalDuration: processedElement ? processedElement.durationTicks : 0
            };

            curScore.endCmd();

            var message = "Added " + addedCount + " lyric(s)";
            if (skippedCount > 0) message += ", skipped " + skippedCount + " rest(s)";
            if (lyricsArray.length > 0) message += ", " + lyricsArray.length + " lyric(s) remaining (ran out of notes)";

            return {
                success: true,
                message: message,
                addedCount: addedCount,
                skippedCount: skippedCount,
                remainingLyrics: lyricsArray,
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Create and position a cursor
    function createCursor(params) {
        if (!curScore) throw new Error("No score open");
        
        // If no params provided, use saved state
        if (!params || Object.keys(params).length === 0) {
            params = selectionState;
        }
        
        var cursor = curScore.newCursor();
        
        // Set cursor to sync with the score's visible input state
        cursor.inputStateMode = Cursor.INPUT_STATE_SYNC_WITH_SCORE;
        
        // Set track (staff and voice)
        if (params.startStaff !== undefined) {
            cursor.staffIdx = params.startStaff;
        }
        if (params.voice !== undefined) {
            cursor.voice = params.voice;
        }
        
        // Position the cursor
        if (params.rewindMode !== undefined) {
            // Use rewindMode: 0 (score start), 1 (selection start), 2 (selection end)
            cursor.rewind(params.rewindMode);
        } else if (params.startTick !== undefined) {
            // Position at a specific tick
            try {
                cursor.rewindToTick(params.startTick);
            } catch (e) {
                console.log("rewindToTick failed, using manual rewind: " + e.toString());
                cursor.rewind(0); // Start of score
                while (cursor.tick < params.startTick && cursor.next()) {
                    // Advance until we reach the tick or the end
                }
            }
        } else if (params.measure !== undefined) {
            // Rewind to specific measure
            try {
                // First try using rewindToMeasure if it exists
                if (typeof cursor.rewindToMeasure === "function") {
                    cursor.rewindToMeasure(params.measure);
                } else {
                    // Fall back to manual navigation
                    cursor.rewind(0); // Start of score
                    var currentMeasure = 0;
                    
                    // Navigate to the target measure
                    while (currentMeasure < params.measure) {
                        if (!cursor.nextMeasure()) {
                            break; // End of score reached
                        }
                        currentMeasure++;
                    }
                    
                    // Position within the measure if specified
                    if (params.position !== undefined) {
                        for (var i = 0; i < params.position; i++) {
                            if (!cursor.next()) {
                                break; // End of measure reached
                            }
                        }
                    }
                }
            } catch (e) {
                throw new Error("Failed to position cursor to measure: " + e.toString());
            }
        } else {
            // Default to start of score if no position specified
            cursor.rewind(0);
        }
        
        // Set note duration for any notes to be added
        if (params.duration) {
            var z = params.duration.numerator || 1;
            var n = params.duration.denominator || 4;
            cursor.setDuration(z, n);
        } else if (params.numerator !== undefined && params.denominator !== undefined) {
            cursor.setDuration(params.numerator, params.denominator);
        }
        
        return cursor;
    }

    // Initialize cursor state - call this when a score is loaded or created
    function initCursorState() {
        if (!curScore) return;
        
        try {
            curScore.startCmd();
            var cursor = curScore.newCursor();
            cursor.rewind(0); // Start at beginning

            var startTick = cursor.tick;
            cursor.next();
            var endTick = cursor.tick;
            var element = cursor.element;
            var processedElement = processElement(element);

            selectionState = {
                startStaff: cursor.staffIdx,
                endStaff: cursor.staffIdx + 1,
                startTick: startTick,
                elements: [processedElement]
            };
            
            // Clear any selection and set initial selection
            curScore.selection.clear();
            var args = [startTick, endTick, 0, 0];
            var success = curScore.selection.selectRange(...args);
            curScore.endCmd();
            
            return (`${args[0]},${args[1]},${args[2]},${args[3]}`);

        } catch (e) {
            curScore.endCmd(true);
            return ("Error initializing cursor state: " + e.toString());
        }
    }


    // Cursor Navigation and Information

    // Select an arbitrary tick range across one or more staves and return every element found in
    // it (per staff, per voice) - a slicing tool for pulling out a cross-measure, multi-staff
    // phrase in one call instead of walking it position by position.
    function selectCustomRange(params) {
        if (!curScore) return { error: "No score open" };

        if (!Object.keys(params).includes("startTick") || !Object.keys(params).includes("endTick") || !Object.keys(params).includes("startStaff") || !Object.keys(params).includes("endStaff")) {
            return { error: "Missing required parameters" };
        }

        var duration = params.endTick - params.startTick;

        try {
            curScore.startCmd();

            var args = [params.startTick, params.endTick, params.startStaff, params.endStaff];
            var success = curScore.selection.selectRange(...args);

            // Walk every segment in the range, capturing each staff/voice's element.
            var elementsMap = {};
            for (var st = params.startStaff; st < params.endStaff; st++) {
                elementsMap[`staff${st}`] = [];
            }

            var cursor = createCursor({ startTick: 0, startStaff: params.startStaff });
            var currentSegment = cursor.segment;
            while (currentSegment && currentSegment.tick < params.startTick) {
                currentSegment = currentSegment.next;
            }

            while (currentSegment && currentSegment.tick < params.endTick) {
                for (var s = params.startStaff; s < params.endStaff; s++) {
                    for (var v = 0; v < 4; v++) {
                        var track = s * 4 + v;
                        var el = currentSegment.elementAt(track);
                        if (el) {
                            var processed = processElement(el);
                            if (processed) {
                                processed.voice = v;
                                processed.startTick = currentSegment.tick;
                                elementsMap[`staff${s}`].push(processed);
                            }
                        }
                    }
                }
                currentSegment = currentSegment.next;
            }

            // update selection state - keep `elements` a flat array (the startStaff's sequence),
            // matching the shape every other function in this plugin expects (addNote's
            // rest-detection, etc. call .length/.filter on it directly). The full per-staff
            // breakdown is still returned below as `rangeElements` for callers who want it.
            selectionState = {
                startStaff: params.startStaff,
                endStaff: params.endStaff,
                startTick: params.startTick,
                elements: elementsMap[`staff${params.startStaff}`] || [],
                totalDuration: duration
            };

            curScore.endCmd();

            return {
                success: success,
                message: "Custom range selected",
                currentSelection: selectionState,
                rangeElements: elementsMap
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return {
                error: e.toString()
            }
        }
    }

    function selectCurrentMeasure() {
        if (!curScore) return { error: "No score open" };

        try {
            // get score summary - must run before our own startCmd below; nesting a
            // curScore command inside another corrupts getScoreSummary()'s measure-boundary
            // walk for the rest of this synchronous call (see goToMeasure for the same fix).
            var scoreSummary = getScoreSummary();

            curScore.startCmd();

            // get cursor
            var cursor = createCursor({ startTick: selectionState.startTick, startStaff: selectionState.startStaff });

            // capture current position
            var currTick = cursor.tick;
            var currStaff = cursor.staffIdx;

            // figure out which measure the selection is in
            var measureIdx = scoreSummary.measures.filter(measure => measure.startTick <= currTick).length - 1;
            var measureStartTick = scoreSummary.measures[measureIdx].startTick;
            var measureElements = scoreSummary.measures[measureIdx].elements[`staff${currStaff}`];

            var totalDuration = measureElements.reduce((a, b) => a + b.durationTicks, 0);
            var measureEndTick = measureStartTick + totalDuration;

            // select measure
            var args = [measureStartTick, measureEndTick, currStaff, currStaff + 1];
            var success = curScore.selection.selectRange(...args);

            // update selection state
            selectionState = {
                startStaff: currStaff,
                endStaff: currStaff + 1,
                startTick: measureStartTick,
                elements: measureElements,
                totalDuration: totalDuration
            }

            curScore.endCmd();

            return { 
                success: success, 
                message: `Selected measure ${measureIdx + 1}`, 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        }
        catch (e) {
            curScore.endCmd(true);
            return { error: e.toString(),
                    measure: measureIdx
                 };
        }
    }

    // insert measure before current measure and select it
    function insertMeasure(params) {
        if (!curScore) return { error: "No score open" };

        try {
            curScore.startCmd();
            cmd("insert-measure");
            curScore.endCmd();

            // sync state to selection
            syncStateToSelection();

            return { 
                success: true, 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }

    function processElement(element) {
        if (!curScore) return { error: "No score open" };

        // A voice track that has never been written to has no segment/element at all
        // (e.g. voice 1 before any note or rest has been placed there) - represent that
        // as an empty placeholder instead of throwing on element.name below.
        if (!element) {
            return { name: "None", durationTicks: 0 };
        }

        var name = element.name;
        var processedElement

        if (name == "Note") {
            processedElement = {
                name: element.name,
                subtype: element.subtype,
                subtypeName: element.subtypeName,
                tempo: element.tempo,
                timesig: element.timesig,
                baseDuration: element.durationType ? getDurationName(element.durationType.type) : null,
                dotted: element.durationType ? element.durationType.dots : null,
                durationTicks: element.actualDuration ? element.actualDuration.ticks : null,
                harmonyType: element.harmonyType,
                accidental: element.accidental,
                accidentalType: element.accidentalType,
                tieBack: element.tieBack,
                tieForward: element.tieForward,
                noteType: element.noteType,
                pitchMidi: element.pitch,
                pitchName: getNoteName(element.pitch),
                tpc: element.tpc,
                spelledName: getTpcName(element.tpc),
                string: element.string,
                fret: element.fret,
                tuplet: element.tuplet ? {
                        durationNumerator: element.tuplet.duration.numerator,
                        durationDenominator: element.tuplet.duration.denominator,
                } : null
            }
        }

        else if (name == "Rest") {
            processedElement = {
                name: element.name,
                subtype: element.subtype,
                subtypeName: element.subtypeName,
                tempo: element.tempo,
                timesig: element.timesig,
                baseDuration: element.durationType ? getDurationName(element.durationType.type) : null,
                dotted: element.durationType ? element.durationType.dots : null,
                durationTicks: element.actualDuration ? element.actualDuration.ticks : null,
                harmonyType: element.harmonyType,
                tuplet: element.tuplet ? {   
                        durationNumerator: element.tuplet.duration.numerator,
                        durationDenominator: element.tuplet.duration.denominator,
                } : null                    
            }
        }

        else if (name == "Chord") {
            processedElement = {
                name: element.name,
                subtype: element.subtype,
                subtypeName: element.subtypeName,
                tempo: element.tempo,
                timesig: element.timesig,
                baseDuration: element.durationType ? getDurationName(element.durationType.type) : null,
                dotted: element.durationType ? element.durationType.dots : null,
                durationTicks: element.actualDuration ? element.actualDuration.ticks : null,
                noteType: element.noteType,
                notes: Object.keys(element.notes).map(k => ({ pitchMidi: element.notes[k].pitch, pitchName: getNoteName(element.notes[k].pitch), tpc: element.notes[k].tpc, spelledName: getTpcName(element.notes[k].tpc), string: element.notes[k].string, fret: element.notes[k].fret, headGroup: element.notes[k].headGroup, tiedForward: element.notes[k].tieForward ? true : false })),
                lyrics: element.lyrics ? Object.keys(element.lyrics).map(k => ({ text: element.lyrics[k].text, verse: element.lyrics[k].verse, syllabic: element.lyrics[k].syllabic })) : [],
                tuplet: element.tuplet ? {
                        durationNumerator: element.tuplet.duration.numerator,
                        durationDenominator: element.tuplet.duration.denominator,
                } : null
            }
        }

        else {
            processedElement = Object.keys(element);
        }

        return processedElement;
    }


    // get current selection
    function syncStateToSelection() {
        if (!curScore) return { error: "No score open" };

        try {
            // Preserve whichever voice was active before this sync - MuseScore's own selection
            // object doesn't carry a "current voice" concept the way our selectionState does.
            var voice = selectionState.voice || 0;

            var currSelection = curScore.selection;
            var startSegment = currSelection.startSegment;
            var endSegment = currSelection.endSegment;
            var startStaff = currSelection.startStaff;
            var endStaff = currSelection.endStaff;


            if (startSegment) {
                // we can move to the start of the selection
                var cursor = createCursor({
                    startTick: startSegment.tick,
                    startStaff: startStaff,
                    voice: voice
                });

                var elements = []

                while (cursor.tick < endSegment.tick) {
                    elements.push(cursor.element);
                    if (!cursor.next()) break;
                }

                elements = elements.map(element => processElement(element));

                var totalDuration = elements.reduce((a, b) => a + b.durationTicks, 0);

                selectionState = {
                    startStaff: startStaff,
                    endStaff: endStaff,
                    startTick: startSegment.tick,
                    elements: elements,
                    totalDuration: totalDuration,
                    voice: voice
                };

                return {
                    success: true,
                    currentSelection: selectionState
                };
            } else {
                // not a range selection, so just select the first element

                var cursor = createCursor(Object.assign({}, selectionState, { voice: voice }));
                var firstElement = curScore.selection.elements[0];

                curScore.selection.select(firstElement);

                cursor.rewind(1); // rewind to beginning of selection

                var processedElement = processElement(firstElement);
                var duration = processedElement.durationTicks;

                var startTick = cursor.tick;
                var staffIdx = cursor.staffIdx;

                // update selection state

                selectionState = {
                    startStaff: staffIdx,
                    endStaff: staffIdx,
                    startTick: startTick,
                    elements: [processedElement],
                    totalDuration: duration,
                    voice: voice
                };
                
                return {
                    success: false, error: "Could not move to start of selection, reset cursor & selection"
                };
            }
        } catch (e) {
            return { success: false,
                     error: e.toString() 
                };
        }
    }

    
    // Get cursor information
    function getCursorInfo(params) {
        if (!curScore) return { error: "No score open" };
        
        try {        
            // Return the saved state which represents the current selection/cursor
            syncStateToSelection();

            return { 
                success: true, 
                currentSelection: selectionState, 
                currentScore: params.verbose == "false" ? null : getScoreSummary()
            };
            
        } catch (e) {
            return { error: e.toString() };
        }
    }
    
    // Set cursor position with unified feedback
    function goToMeasure(params) {
        if (!curScore) return { error: "No score open" };
        
        try {
            // check for params
            if (!params.measure) {
                return { error: "Measure parameter must be specified" };
            }

            // get relevant measure info - must run BEFORE our own startCmd below, since
            // getScoreSummary() opens/closes its own curScore command; nesting it inside
            // this function's command corrupts the measure-boundary walk (cursor.nextMeasure()
            // stops advancing) for the remainder of this synchronous call.
            var score = getScoreSummary();
            var measure = score.measures[params.measure - 1];
            var startTick = measure.startTick;
            var voice = params.voice !== undefined ? params.voice : (selectionState.voice || 0);

            // Start command for undo
            curScore.startCmd();

            // Position the cursor to read the element/duration at this tick - ALWAYS via
            // voice 0, regardless of the requested voice. Creating a cursor with .voice set
            // to a track that has no content yet at this tick (e.g. voice 1 before anything
            // is written there) and then reading .element/.tick was found to corrupt the
            // score's measure/segment traversal for the rest of the MuseScore session (a
            // real engine-level issue). The requested voice is still recorded in
            // selectionState below for whatever action runs next (addNote/addRest, which
            // create their own content and don't need to read an empty spot first).
            var cursor = createCursor({ startTick: startTick, startStaff: selectionState.startStaff, voice: 0 });

            var element = processElement(cursor.element);
            var staffIdx = selectionState.startStaff;
            curScore.selection.clear();
            // A zero-length range (an empty/untouched voice track has no element here, so
            // durationTicks is 0) is not a valid selection - skip it rather than risk
            // selectRange() throwing or leaving curScore.selection in a bad state.
            if (element.durationTicks > 0) {
                curScore.selection.selectRange(startTick, startTick + element.durationTicks, staffIdx, staffIdx + 1);
            }

            // Save state
            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx + 1,
                startTick: startTick,
                elements: [element],
                totalDuration: element.durationTicks,
                voice: voice
            };
            
            curScore.endCmd();
            
            return { 
                success: true, 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            if (curScore) curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }

    // move to next staff

    function prevStaff(params) {
        if (!curScore) return { error: "No score open" };

        try {
        
            // Start command for undo
            curScore.startCmd();

            // sync state to selection
            syncStateToSelection();

            // check if at first staff, and if so return failure
            if (selectionState.startStaff == 0) {
                return { success: false, message: "Already at first staff" };
            }

            // otherwise, move to previous staff

            // select current measure
            selectCurrentMeasure();

            var newStartStaff = selectionState.startStaff - 1
            var newEndStaff = newStartStaff + 1

            curScore.selection.clear();

            var cursor = createCursor({ startTick: selectionState.startTick, startStaff: newStartStaff });

            var newElement = processElement(cursor.element);
            var newDuration = newElement.durationTicks;
            
            curScore.selection.selectRange(selectionState.startTick, selectionState.startTick + newDuration, newStartStaff, newEndStaff);

            // Save state
            selectionState = {
                startStaff: newStartStaff,
                endStaff: newEndStaff,
                startTick: selectionState.startTick,
                elements: [newElement],
                totalDuration: newDuration
            }

            curScore.endCmd();

            return {
                success: true, 
                currentSelection: selectionState,
                currentScore: params.verbose == "false" ? null : getScoreSummary()
            };

        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return {
                success: false,
                error: e.toString()
            }
        }
    }

    function nextStaff(params) {
        if (!curScore) return { error: "No score open" };

        try {

            // Start command for undo
            curScore.startCmd();

            // sync state to selection
            syncStateToSelection();

            // check if at last staff, and if so return failure
            if (selectionState.endStaff == curScore.nstaves) {
                return { success: false, message: "Already at last staff" };
            }

            // otherwise, move to next staff

            // select current measure
            selectCurrentMeasure();

            var newStartStaff = selectionState.endStaff
            var newEndStaff = newStartStaff + 1

            curScore.selection.clear();

            var cursor = createCursor({ startTick: selectionState.startTick, startStaff: newStartStaff });

            var newElement = processElement(cursor.element);
            var newDuration = newElement.durationTicks;
            
            var args = [selectionState.startTick, selectionState.startTick + newDuration, newStartStaff, newEndStaff];
            var success = curScore.selection.selectRange(...args);

            curScore.endCmd();

            // Save state
            selectionState = {
                startStaff: newStartStaff,
                endStaff: newEndStaff,
                startTick: selectionState.startTick,
                elements: [newElement],
                totalDuration: newDuration
            }


            return { 
                    success: success, 
                    args: args,
                    currentSelection: selectionState,
                    currentScore: params.verbose == "false" ? null : getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }

    // Switch which voice (0-3) subsequent actions read/write on the current staff, without
    // otherwise moving the cursor. Every navigation/write action threads selectionState.voice
    // through automatically once set here, until changed again or a staff change resets it.
    function setVoice(params) {
        if (!curScore) return { error: "No score open" };
        if (params.voice === undefined || params.voice < 0 || params.voice > 3) {
            return { error: "voice must be specified as an integer 0-3" };
        }

        curScore.startCmd();
        try {
            // Deliberately does NOT create a cursor or read cursor.element at the current
            // position. Positioning a cursor's .voice to a track that has never had content
            // written at this tick (e.g. voice 1 before anything is placed there) and then
            // reading .element/.tick was found to corrupt the score's measure/segment
            // traversal for the rest of the MuseScore session (a real engine-level issue, not
            // something fixable in JS) - so this just flips the voice flag on our own saved
            // state and leaves any real cursor work to whatever action runs next (addNote/
            // addRest, which create their own content and don't need to read an empty spot).
            selectionState = {
                startStaff: selectionState.startStaff,
                endStaff: selectionState.endStaff,
                startTick: selectionState.startTick,
                elements: selectionState.elements,
                totalDuration: selectionState.totalDuration,
                voice: params.voice
            };

            curScore.endCmd();
            return {
                success: true,
                message: "Switched to voice " + params.voice,
                currentSelection: selectionState
            };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Move to next element
    function nextElement(params) {
        if (!curScore) return { error: "No score open" };
        
        try {
            // Start command for undo
            curScore.startCmd();

            // sync state to selection
            syncStateToSelection();

            // if range of elements selected, go to end of range
            var startTick = selectionState.startTick;
            if (selectionState.elements.length > 1) {
                var allButLast = selectionState.elements.slice(0, selectionState.elements.length - 1);
                var duration = allButLast.reduce((a, b) => a + b.durationTicks, 0);
                startTick += duration;
            }
            
            var cursor = createCursor({ startTick: startTick, startStaff: selectionState.startStaff, voice: selectionState.voice || 0 });

            // Move to next element
            var success
            var numElements = params.numElements || 1;
            for (var i = 0; i < numElements; i++) {
                success = cursor.next();
            }

            if (success) {
                // Update selection to match new cursor position
                curScore.selection.clear();
                var staffIdx = cursor.staffIdx;
                var startTick = cursor.tick;
                var processedElement = processElement(cursor.element);
                var duration = processedElement.durationTicks;
                var endTick = startTick + duration;
                var lastTick = curScore.lastSegment.tick

                if (endTick >= lastTick) {
                    // can't select the last element, so need to add a measure at the end
                    cmd("append-measure");
                }

                curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx + 1);

                // Update saved state
                selectionState = {
                    startStaff: staffIdx,
                    endStaff: staffIdx + 1,
                    startTick: startTick,
                    elements: [processedElement],
                    totalDuration: duration,
                    voice: cursor.voice !== undefined ? cursor.voice : (selectionState.voice || 0)
                };

            }
            
            curScore.endCmd();
            
            if (success) {
                return { 
                    success: true, 
                    currentSelection: selectionState,
                    currentScore: params.verbose == "false" ? null : getScoreSummary()
                };
            } else {
                return { 
                    message: "End of score reached", 
                    success: false, 
                    currentSelection: selectionState,
                    currentScore: params.verbose == "false" ? null : getScoreSummary()
                };
            }
        } catch (e) {
            if (curScore) curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }


    // Move to previous element with unified feedback
    function prevElement(params) {
        if (!curScore) return { error: "No score open" };
        
        try {
            // Start command for undo
            curScore.startCmd();

            // sync state to selection
            syncStateToSelection();
            
            var cursor = createCursor({ startTick: selectionState.startTick, startStaff: selectionState.startStaff, voice: selectionState.voice || 0 });

            var endTick = cursor.tick;

            // Move to previous element
            var success

            var numElements = params.numElements || 1;
            for (var i = 0; i < numElements; i++) {
                success = cursor.prev();
            }

            var startTick = cursor.tick;
            
            if (success) {
                // Update selection to match new cursor position
                curScore.selection.clear();
                var staffIdx = cursor.staffIdx;
                curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx + 1);

                var processedElement = processElement(cursor.element);

                // Update saved state
                selectionState = {
                    startStaff: staffIdx,
                    endStaff: staffIdx + 1,
                    startTick: startTick,
                    elements: [processedElement],
                    totalDuration: endTick - startTick,
                    voice: cursor.voice !== undefined ? cursor.voice : (selectionState.voice || 0)
                };
            }

            curScore.endCmd();

            if (success) {
                return {
                    success: true,
                    currentSelection: selectionState,
                    currentScore: params.verbose == "false" ? null : getScoreSummary()
                };
            } else {
                return {
                    message: "Beginning of score reached",
                    success: false, 
                    currentSelection: selectionState, 
                    currentScore: params.verbose == "false" ? null : getScoreSummary()
                };
            }
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }

    // Note and Measure Operations
    
    // Add note at cursor position with unified feedback
    function addNote(params) {
        if (!curScore) {
            return { error: "No score open" };
        }

        if (!params.pitch || !params.duration || !params.duration.numerator || !params.duration.denominator || !Object.keys(params).includes("advanceCursorAfterAction")) {
            return { error: "Pitch and duration must be specified. Pitch must be specified as a midi pitch value. Duration must be specified as { numerator: int, denominator: int }. advanceCursorAfterAction must be true or false" };
        }

        // Start command for undo
        curScore.startCmd();
        
        try {
            // sync state to selection
            syncStateToSelection();

            // Create cursor - pass an explicit voice override for this call if given, else
            // createCursor() falls back to the full (persisted) selectionState as-is.
            var cursor = params.voice !== undefined
                ? createCursor(Object.assign({}, selectionState, { voice: params.voice }))
                : createCursor();

            cursor.setDuration(params.duration.numerator, params.duration.denominator);

            // Add the note
            if (params.pitch !== undefined) {

                // addToChord: explicit override when given; otherwise auto-detect from whether
                // the current position is a rest (rest -> replace it; note/chord -> stack onto it).
                var addToChord;
                if (Object.keys(params).includes("addToChord")) {
                    addToChord = params.addToChord === true;
                } else {
                    // Only stack onto an existing Chord/Note - a Rest or an empty/untouched
                    // voice track ("None", see processElement) both mean there's nothing to add to.
                    var hasRealChordOrNote = selectionState.elements.length > 0 && selectionState.elements.some(element => element.name == "Chord" || element.name == "Note");
                    addToChord = hasRealChordOrNote;
                }

                if (addToChord == false) {
                    cursor.addNote(params.pitch, false);
                } else {
                    cursor.addNote(params.pitch, true);
                }

                // Explicit tablature placement (guitar/bass tab staves): override MuseScore's
                // automatic string/fret assignment so the chord is voiced in a physically
                // playable position instead of whatever string happens to be free.
                if (params.string !== undefined && params.fret !== undefined) {
                    var justAddedChord = cursor.element;
                    if (justAddedChord && justAddedChord.notes && justAddedChord.notes.length > 0) {
                        // The just-added note is the newest entry in the chord's notes array.
                        var newNote = justAddedChord.notes[justAddedChord.notes.length - 1];
                        newNote.string = params.string;
                        newNote.fret = params.fret;
                    }
                }

                // reselect the currently relevant segment
                cursor.rewindToTick(selectionState.startTick);

                if (params.advanceCursorAfterAction == true) {
                    cursor.next();
                }

                var element = cursor.element;
                var processedElement = processElement(element);
                var duration = processedElement.durationTicks;
                var startTick = cursor.tick;
                var endTick = startTick + duration;

                var staffIdx = cursor.staffIdx;

                // Update selection state
                selectionState = {
                    startStaff: staffIdx,
                    endStaff: staffIdx,
                    startTick: startTick,
                    elements: [processedElement],
                    totalDuration: duration,
                    voice: cursor.voice !== undefined ? cursor.voice : (selectionState.voice || 0)
                }

                curScore.selection.clear();
                curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx);

                curScore.endCmd();
                return {
                    success: true,
                    message: "Note added with pitch " + params.pitch + " at tick " + cursor.tick,
                    currentSelection: selectionState,
                    currentScore: getScoreSummary()
                };
            } else {
                curScore.endCmd(true); // Rollback
                return { error: "Pitch must be specified as a midi pitch value" };
            }
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }


    // Add a rest at cursor position
    function addRest(params) {
        if (!curScore) return { error: "No score open" };
        
        if (!params.duration || !params.duration.numerator || !params.duration.denominator || !Object.keys(params).includes("advanceCursorAfterAction")) {
            return { error: "Duration must be specified as { numerator: int, denominator: int }. advanceCursorAfterAction must be true or false" };
        }

        // Start command for undo
        curScore.startCmd();
        
        try {
            // sync state to selection
            syncStateToSelection();

            var cursor = params.voice !== undefined
                ? createCursor(Object.assign({}, selectionState, { voice: params.voice }))
                : createCursor();

            // Add the rest
            cursor.setDuration(params.duration.numerator, params.duration.denominator)

            cursor.addRest();

            cursor.rewindToTick(selectionState.startTick);

            if (params.advanceCursorAfterAction == true) {
                cursor.next();
            }

            // reselect the currently relevant segment
            var startTick = cursor.tick;

            var element = cursor.element;
            var processedElement = processElement(element);
            var duration = processedElement.durationTicks;
            var endTick = cursor.tick + duration;
            var staffIdx = cursor.staffIdx;

            // Update selection state
            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx,
                startTick: startTick,
                elements: [processedElement],
                totalDuration: duration,
                voice: cursor.voice !== undefined ? cursor.voice : (selectionState.voice || 0)
            }

            // Update selection to match cursor position
            curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx);

            curScore.endCmd();
            return { 
                success: true, 
                message: "Rest added", 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Add a tuplet
    function addTuplet(params) {
        if (!curScore) return { error: "No score open" };
        
        if (!params.ratio || !params.duration || !params.duration.numerator || !params.duration.denominator || !params.ratio.numerator || !params.ratio.denominator || !Object.keys(params).includes("advanceCursorAfterAction")) {
            return { error: "Ratio and duration must be specified in the form { numerator: int, denominator: int }. advanceCursorAfterAction must be true or false" };
        }
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            var cursor = createCursor();

            cursor.setDuration(params.duration.numerator, params.duration.denominator);
            
            // Create ratio fraction
            var ratio = fraction(params.ratio.numerator, params.ratio.denominator);
            
            // Create duration fraction
            var duration = fraction(params.duration.numerator, params.duration.denominator);
            
            // Add the tuplet
            cursor.addTuplet(ratio, duration);

            // reselect the currently relevant segment

            cursor.next();

            if (params.advanceCursorAfterAction == true) {
                cursor.next();
            }

            var endTick = cursor.tick;
            cursor.prev();
            var startTick = cursor.tick;
            var staffIdx = cursor.staffIdx;

            // Update selection state
            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx,
                startTick: startTick,
                elements: [processElement(cursor.element)],
                totalDuration: cursor.element.durationTicks
            }

            curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx);
        
            curScore.endCmd();

            return { 
                success: true, 
                message: "Tuplet " + params.ratio.numerator + ":" + 
                        params.ratio.denominator + " added",
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Go to the beginning of the last measure
    function goToFinalMeasure(params) {
        if (!curScore) return { error: "No score open" };

        // Start command for undo
        curScore.startCmd();

        var cursor = createCursor({ startTick: 0 });
        var count = 0;
        var startTick;


        try {

            while (cursor.nextMeasure()) {
                startTick = cursor.tick;
                count++;
            }

            // if already at the end, do nothing
            if (count == 0) {
                return { 
                    success: false, 
                    message: "Already at the last measure",
                    currentSelection: selectionState,
                    currentScore: getScoreSummary()
                };
            }

            // Update the selection and state
            curScore.selection.clear();
            
            // reset cursor
            cursor.rewindToTick(startTick);
            var success = cursor.next();
            var endTick = cursor.tick;

            var staffIdx = cursor.staffIdx;
            curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx);
            
            // Update saved state
            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx,
                startTick: startTick,
                endTick: endTick,
                element: cursor.element ? cursor.element.name : null
            };

            curScore.endCmd();

            return { 
                success: true, 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }

    }

    // Add measures to the score
    function appendMeasure(params) {
        if (!curScore) return { error: "No score open" };
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            var count = params.count || 1;
            
            for (var i = 0; i < count; i++) {
                cmd("append-measure");
            }
            
            curScore.endCmd();
            return { 
                success: true, 
                message: count + " measure(s) appended", 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Delete current selection
    function deleteSelection(params) {
        if (!curScore) return { error: "No score open" };
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            var cursor = createCursor({
                measure: params.measure
            });
            
            cmd("delete");
            
            curScore.endCmd();

            return { 
                success: true, 
                message: "Selection deleted", 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Staff and Instrument Operations
    
    // Add a new staff/instrument
    function addInstrument(params) {
        if (!curScore) return { error: "No score open" };
        
        if (!params.instrumentId) {
            return { error: "Instrument ID must be specified" };
        }
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            // Add the part with the specified instrument
            curScore.appendPart(params.instrumentId);
            
            curScore.endCmd();
            return { 
                success: true, 
                message: "Instrument " + params.instrumentId + " added" 
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // KNOWN LIMITATION: confirmed non-functional via live testing - setting staff.invisible
    // returns success:true and the assignment doesn't throw, but it does not actually take
    // effect (a fresh get_score afterward still shows visible:true). Left in for reference /
    // in case a future MuseScore build fixes it, but deliberately excluded from the
    // validCommands whitelist - do not re-add without re-verifying.
    function setStaffMute(params) {
        if (!curScore) return { error: "No score open" };
        
        if (params.staff === undefined) return { error: "No staff specified" };
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            var staff;
            
            // Get staff through staves array or staff method
            if (curScore.staves && curScore.staves.length > params.staff) {
                staff = curScore.staves[params.staff];
            } else if (typeof curScore.staff === "function") {
                staff = curScore.staff(params.staff);
            }
            
            if (staff) {
                staff.invisible = params.mute ? true : false;
                curScore.endCmd();
                return { 
                    success: true, 
                    message: "Staff " + (params.mute ? "muted" : "unmuted") 
                };
            } else {
                curScore.endCmd(true); // Rollback
                return { error: "Staff not found" };
            }
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Change instrument sound - TBD
    function setInstrumentSound(params) {
        if (!curScore) return { error: "No score open" };
        
        if (params.staff === undefined) return { error: "No staff specified" };
        if (!params.instrumentId) return { error: "No instrument ID specified" };
        
        // This is a placeholder - implementation depends on MuseScore 4's API
        // Start command for undo
        curScore.startCmd();
        
        try {
            // Try to trigger instrument change through command
            cmd("instruments");
            
            curScore.endCmd();
            return { 
                success: true, 
                message: "Instrument dialog opened, manual selection required" 
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Time Signature
    
    // Set time signature
    function setTimeSignature(params) {
        if (!curScore) return { error: "No score open" };
        
        if (!params.numerator || !params.denominator) {
            return { error: "Both numerator and denominator must be specified" };
        }
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            var cursor = createCursor();
            var currTick = cursor.tick;
            var currElement = processElement(cursor.element);
            var currStaff = cursor.staffIdx;

            var ts = newElement(Element.TIMESIG)
            ts.timesig = fraction(params.numerator, params.denominator);
            cursor.add(ts)

            // reset selection to previously selected element
            curScore.selection.selectRange(currTick, currTick + currElement.durationTicks, currStaff, currStaff);
            
            curScore.endCmd();
            return { 
                success: true, 
                message: "Time signature set to " + params.numerator + "/" + params.denominator + " for this measure until the next measure with a specified time signature",
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }

    // Add a tempo marking at the current cursor position
    function setTempo(params) {
        if (!curScore) return { error: "No score open" };
        if (!params.bpm) return { error: "bpm must be specified" };

        curScore.startCmd();
        try {
            var cursor = createCursor();

            var tempo = newElement(Element.TEMPO_TEXT);
            tempo.tempo = params.bpm / 60.0;
            tempo.text = "♩ = " + params.bpm;
            cursor.add(tempo);

            curScore.endCmd();
            return {
                success: true,
                message: "Tempo set to " + params.bpm + " BPM at the current cursor position",
                currentSelection: selectionState
            };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Set the score's title (workTitle meta tag and, where present, the title frame text)
    function setTitle(params) {
        if (!curScore) return { error: "No score open" };
        if (params.title === undefined) return { error: "title must be specified" };

        curScore.startCmd();
        try {
            curScore.setMetaTag("workTitle", params.title);
            // Fall back methods for the visible title frame text, if MuseScore exposes one -
            // these are best-effort since the plugin API doesn't always expose it directly.
            if (curScore.title !== undefined) {
                try { curScore.title = params.title; } catch (e2) { /* ignore */ }
            }

            curScore.endCmd();
            return {
                success: true,
                message: "Title set to \"" + params.title + "\""
            };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Score Information + Helper Functions
    
    // Get note names
    function getNoteName(note) {
        const noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
        var noteName = noteNames[note % 12];
        return noteName;
    }

    // Decodes a note's actual notated spelling (sharp vs flat, double-accidentals) from its TPC
    // (tonal pitch class), independent of getNoteName's fixed sharps-only display. Index == TPC
    // directly (TPC 14 = C); TPC -1 (Fbb) is special-cased since JS can't index arrays at -1.
    function getTpcName(tpc) {
        if (tpc === -1) return "Fbb";
        const tpcNames = [
            "Cbb", "Gbb", "Dbb", "Abb", "Ebb", "Bbb", "Fb",
            "Cb",  "Gb",  "Db",  "Ab",  "Eb",  "Bb",  "F",
            "C",   "G",   "D",   "A",   "E",   "B",   "F#",
            "C#",  "G#",  "D#",  "A#",  "E#",  "B#",  "F##",
            "C##", "G##", "D##", "A##", "E##", "B##", "F###"
        ];
        if (tpc >= 0 && tpc < tpcNames.length) return tpcNames[tpc];
        return "Unknown(" + tpc + ")";
    }

    function getDurationName(duration) {
        const durationNames = ["LONG","BREVE","WHOLE","HALF","QUARTER","EIGHTH","16TH","32ND","64TH","128TH","256TH","512TH","1024TH","ZERO","MEASURE","INVALID"];

        var durationName = durationNames[duration];
        return durationName;
    }

    function getScoreSummary() {
        if (!curScore) return { error: "No score open" };

         try {

            // save selectionState to restore 
            var tempSelectionState = selectionState;

            var score = {
                numMeasures: curScore.nmeasures,
                measures: [],
                staves: []
            };
            
            // Analyze each staff
            for (var i = 0; i < curScore.nstaves; i++) {
                var staff;
                
                // Get staff through staves array or staff method
                if (curScore.staves && curScore.staves.length > i) {
                    staff = curScore.staves[i];
                } else if (typeof curScore.staff === "function") {
                    staff = curScore.staff(i);
                }
                
                if (staff) {
                    // Staff itself doesn't reliably expose instrument name info in the
                    // MuseScore 4 plugin API - that lives on the Part it belongs to.
                    // Capture from both places defensively so whichever exists comes through.
                    var part = staff.part;
                    score.staves.push({
                        name: `staff${i}`,
                        shortName: staff.shortName,
                        longName: part ? part.longName : undefined,
                        partShortName: part ? part.shortName : undefined,
                        instrumentId: part ? part.instrumentId : undefined,
                        visible: !staff.invisible
                    });
                } else {
                    score.staves.push({
                        name: `staff${i}`
                    });
                }
            }

            // Analyze each measure
            curScore.startCmd();

            // Initialize cursor - use a plain cursor, NOT createCursor()'s, which sets
            // inputStateMode = INPUT_STATE_SYNC_WITH_SCORE. That mode continuously re-syncs
            // to the score's live note-input voice (a document-wide property, not just our
            // JS selectionState) on every cursor operation, silently overriding any explicit
            // cursor.voice we set here - if an earlier action left that live voice on 1+,
            // measure/segment traversal breaks on any voice track that has no content.
            var cursor = curScore.newCursor();
            cursor.voice = 0;
            cursor.rewind(0);

            // first, just capture the measures and their boundaries

            var measureBoundaries = [];

            for (var i = 0; i < curScore.nmeasures; i++) {
                // create measure
                var measure = {
                    measure: i+1, 
                    startTick: 0,
                    numElements: 0, 
                    elements: {}
                };

                // add staff params to the elements obj
                for (var j = 0; j < curScore.nstaves; j++) {
                    measure.elements[`staff${j}`] = [];
                }

                // track measure boundaries
                measure.startTick = cursor.tick;
                measureBoundaries.push(cursor.tick);

                // add measure to score
                score.measures.push(measure);

                // set cursor to start of next measure
                cursor.nextMeasure();
            }

            // now, iterate through the staffs and process each measure's elements

            // Read all four voices of every staff by walking the segments and asking each one for the
            // element on track (staff * 4 + voice). No cursor voice is ever set, so empty voices cost
            // nothing and cannot corrupt the score state (approach taken from ghchen99/mcp-musescore).
            for (var k = 0; k < curScore.nstaves; k++) {
                cursor.rewind(0);
                var seg = cursor.segment;

                while (seg) {
                    var measureIdx = -1;
                    for (var v = 0; v < 4; v++) {
                        var element = seg.elementAt(k * 4 + v);
                        if (!element || (element.type !== Element.CHORD && element.type !== Element.REST)) continue;
                        if (measureIdx < 0) measureIdx = measureBoundaries.filter(tick => tick <= seg.tick).length - 1;

                        score.measures[measureIdx].numElements++;
                        var processedElement = processElement(element);
                        processedElement.startTick = seg.tick;
                        processedElement.voice = v;
                        score.measures[measureIdx].elements[`staff${k}`].push(processedElement);
                    }
                    seg = seg.next;
                }
            }

            // Capture chord symbols (Harmony annotations), walking segments directly
            // per measure rather than piggybacking on a staff's note cursor - a staff
            // with a long sustained note can skip over segments that hold nothing but
            // an annotation, silently hiding chord symbols placed mid-measure.
            var measureForHarmony = curScore.firstMeasure;
            var harmonyMeasureIdx = 0;
            while (measureForHarmony) {
                var harmonySegment = measureForHarmony.firstSegment;
                while (harmonySegment) {
                    if (harmonySegment.annotations) {
                        for (var h = 0; h < harmonySegment.annotations.length; h++) {
                            if (harmonySegment.annotations[h].name === "Harmony") {
                                if (!score.measures[harmonyMeasureIdx].chordSymbols) {
                                    score.measures[harmonyMeasureIdx].chordSymbols = [];
                                }
                                score.measures[harmonyMeasureIdx].chordSymbols.push({
                                    text: harmonySegment.annotations[h].text,
                                    startTick: harmonySegment.tick
                                });
                            } else {
                                var an = harmonySegment.annotations[h];
                                if (!score.measures[harmonyMeasureIdx].annotations) {
                                    score.measures[harmonyMeasureIdx].annotations = [];
                                }
                                score.measures[harmonyMeasureIdx].annotations.push({
                                    type: an.name,
                                    text: an.text,
                                    startTick: harmonySegment.tick,
                                    staff: an.track !== undefined ? Math.floor(an.track / 4) : undefined
                                });
                            }
                        }
                    }
                    harmonySegment = harmonySegment.nextInMeasure;
                }
                measureForHarmony = measureForHarmony.nextMeasure;
                harmonyMeasureIdx++;
            }

            // Reset cursor state - use a RANGE selection (selectRange), not select() on a
            // bare element. select() produces a "list" selection with no startSegment/
            // endSegment, which forces a later syncStateToSelection() call down its fragile
            // single-element branch - whose cursor.rewind(1) call was found to reset the
            // cursor back to tick 0 instead of preserving the actual position.
            cursor.staffIdx = tempSelectionState.startStaff;
            cursor.rewindToTick(tempSelectionState.startTick);
            var resetElement = processElement(cursor.element);
            if (resetElement.durationTicks > 0) {
                curScore.selection.selectRange(tempSelectionState.startTick, tempSelectionState.startTick + resetElement.durationTicks, tempSelectionState.startStaff, tempSelectionState.startStaff + 1);
            }

            curScore.endCmd();

            return score;
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }

    // Get score structure. Optional params: staves (array of 0-based staff indexes),
    // startMeasure / endMeasure (1-based, inclusive), summary (true = per-staff overview only).
    function getScore(params) {
        if (!curScore) return { error: "No score open" };
        params = params || {};

        try {
            var full = getScoreSummary();
            if (full.error) return { error: full.error };

            var wanted = Array.isArray(params.staves) ? params.staves : null;
            var sm = params.startMeasure !== undefined ? params.startMeasure : 1;
            var em = params.endMeasure !== undefined ? params.endMeasure : full.numMeasures;

            if (params.summary === true) {
                var perStaff = [];
                for (var si = 0; si < full.staves.length; si++) {
                    if (wanted && wanted.indexOf(si) < 0) continue;
                    var noteCount = 0, withNotes = [], withLyrics = 0;
                    for (var mi = 0; mi < full.measures.length; mi++) {
                        var els = full.measures[mi].elements["staff" + si] || [];
                        var has = false;
                        for (var ei = 0; ei < els.length; ei++) {
                            if (els[ei].name === "Chord") {
                                has = true;
                                noteCount += els[ei].notes.length;
                                withLyrics += (els[ei].lyrics || []).length;
                            }
                        }
                        if (has) withNotes.push(mi + 1);
                    }
                    // collapse measure numbers into [start, end] runs
                    var runs = [];
                    for (var k = 0; k < withNotes.length; k++) {
                        if (runs.length && runs[runs.length - 1][1] === withNotes[k] - 1) runs[runs.length - 1][1] = withNotes[k];
                        else runs.push([withNotes[k], withNotes[k]]);
                    }
                    perStaff.push({ staff: si, name: full.staves[si].longName, notes: noteCount, lyrics: withLyrics, measureRunsWithNotes: runs });
                }
                var chordMeasures = full.measures.filter(function (m) { return m.chordSymbols && m.chordSymbols.length; }).map(function (m) { return m.measure; });
                return { success: true, analysis: { numMeasures: full.numMeasures, staves: full.staves, perStaff: perStaff, measuresWithChordSymbols: chordMeasures.length } };
            }

            var out = [];
            for (var m2 = 0; m2 < full.measures.length; m2++) {
                var meas = full.measures[m2];
                if (meas.measure < sm || meas.measure > em) continue;
                if (wanted) {
                    var filtered = {};
                    for (var w = 0; w < wanted.length; w++) filtered["staff" + wanted[w]] = meas.elements["staff" + wanted[w]] || [];
                    meas = { measure: meas.measure, startTick: meas.startTick, numElements: meas.numElements, elements: filtered, chordSymbols: meas.chordSymbols, annotations: meas.annotations };
                }
                out.push(meas);
            }
            return { success: true, analysis: { numMeasures: full.numMeasures, measures: out, staves: full.staves } };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    // ---- Range / notation helpers and actions -------------------------------------------------
    // Convention for all tick ranges below: startTick inclusive, endTick exclusive; staff is
    // 0-based. Voice 0 only (voices > 0 are deliberately not touched - see setNoteHeads).

    function plainCursorAt(staff, tick) {
        var c = curScore.newCursor();
        c.staffIdx = staff;
        c.voice = 0;
        c.rewindToTick(tick);
        return c;
    }

    function needNumbers(params, names) {
        for (var i = 0; i < names.length; i++) {
            if (params[names[i]] === undefined || params[names[i]] === null) return names[i] + " must be specified";
        }
        return null;
    }

    function selectTickRange(staff, startTick, endTick) {
        curScore.selection.clear();
        curScore.selection.selectRange(startTick, endTick, staff, staff + 1);
    }

    // Selects notes as a LIST (like clicking them). onlyEndpoints=true selects just the first note
    // of the first chord and of the last chord in the range (what slurs / hairpins span between).
    // cmd()-based actions were found to ignore a plain range selection made via selectRange().
    // Returns the number of notes selected.
    function selectNotesAsList(staff, startTick, endTick, onlyEndpoints) {
        var c = plainCursorAt(staff, startTick);
        var chords = [];
        while (c.segment && c.tick < endTick) {
            var el = c.element;
            if (el && el.type === Element.CHORD) chords.push(el);
            if (!c.next()) break;
        }
        curScore.selection.clear();
        var picked = 0;
        if (chords.length === 0) return 0;
        var chosen = onlyEndpoints ? (chords.length > 1 ? [chords[0], chords[chords.length - 1]] : [chords[0]]) : chords;
        for (var k = 0; k < chosen.length; k++) {
            var notes = onlyEndpoints ? [chosen[k].notes[0]] : chosen[k].notes;
            for (var i = 0; i < notes.length; i++) {
                curScore.selection.select(notes[i], picked > 0);
                picked++;
            }
        }
        return picked;
    }

    function addDynamic(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "tick", "dynamic"]);
        if (bad) return { error: bad };
        curScore.startCmd();
        try {
            var c = plainCursorAt(params.staff, params.tick);
            var d = newElement(Element.DYNAMIC);
            d.text = params.dynamic;
            c.add(d);
            curScore.endCmd();
            return { success: true, message: "Dynamic '" + params.dynamic + "' added at tick " + c.tick + " on staff " + params.staff };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Crescendo / diminuendo hairpin over the range, via the same actions MuseScore's UI uses
    // ("add-hairpin" / "add-hairpin-reverse"). Like the other cmd()-based actions below it runs
    // OUTSIDE startCmd()/endCmd(): these actions manage their own undo step, and when nested in the
    // plugin's they were dispatched (visible in the MuseScore log) but left no visible change.
    function addHairpin(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "startTick", "endTick", "type"]);
        if (bad) return { error: bad };
        if (params.type !== "crescendo" && params.type !== "diminuendo") return { error: 'type must be "crescendo" or "diminuendo"' };
        try {
            if (selectNotesAsList(params.staff, params.startTick, params.endTick, true) === 0) throw new Error("no notes in range");
            cmd(params.type === "crescendo" ? "add-hairpin" : "add-hairpin-reverse");
            return { success: true, message: params.type + " hairpin requested on staff " + params.staff + " [" + params.startTick + ", " + params.endTick + ")" };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    // Articulation on every chord in the range (rests are skipped).
    function addArticulation(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "startTick", "endTick", "articulation"]);
        if (bad) return { error: bad };
        var symbols = {
            staccato: "articStaccatoAbove",
            staccatissimo: "articStaccatissimoAbove",
            accent: "articAccentAbove",
            tenuto: "articTenutoAbove",
            marcato: "articMarcatoAbove",
            "tenuto-staccato": "articTenutoStaccatoAbove"
        };
        if (!symbols[params.articulation]) return { error: "articulation must be one of: " + Object.keys(symbols).join(", ") };
        curScore.startCmd();
        try {
            var symId = SymId[symbols[params.articulation]];
            if (symId === undefined) throw new Error("SymId." + symbols[params.articulation] + " not available");
            var c = plainCursorAt(params.staff, params.startTick);
            var count = 0;
            while (c.segment && c.tick < params.endTick) {
                var el = c.element;
                if (el && el.type === Element.CHORD) {
                    var a = newElement(Element.ARTICULATION);
                    a.symbol = symId;
                    c.add(a);
                    count++;
                }
                if (!c.next()) break;
            }
            curScore.endCmd();
            return { success: true, message: params.articulation + " added to " + count + " chord(s)" };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Text at a position. kind: staff | system | rehearsal | tempo (tempo marking text, e.g. "rit.")
    function addText(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "tick", "kind", "text"]);
        if (bad) return { error: bad };
        var kinds = { staff: "STAFF_TEXT", system: "SYSTEM_TEXT", rehearsal: "REHEARSAL_MARK", tempo: "TEMPO_TEXT" };
        if (!kinds[params.kind]) return { error: "kind must be one of: " + Object.keys(kinds).join(", ") };
        curScore.startCmd();
        try {
            var type = Element[kinds[params.kind]];
            if (type === undefined) throw new Error("Element." + kinds[params.kind] + " not available in this build");
            var c = plainCursorAt(params.staff, params.tick);
            var t = newElement(type);
            t.text = params.text;
            c.add(t);
            curScore.endCmd();
            return { success: true, message: params.kind + " text '" + params.text + "' added at tick " + c.tick };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Slur over the range (same action as pressing S with the range selected). Runs outside
    // startCmd()/endCmd() - see addHairpin.
    function addSlur(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "startTick", "endTick"]);
        if (bad) return { error: bad };
        try {
            if (selectNotesAsList(params.staff, params.startTick, params.endTick, true) === 0) throw new Error("no notes in range");
            cmd("add-slur");
            return { success: true, message: "Slur requested on staff " + params.staff + " [" + params.startTick + ", " + params.endTick + ")" };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    // Ties every note in the range to the next note of the same pitch. The notes are selected as
    // a list (like clicking them) rather than as a range, and the action runs outside
    // startCmd()/endCmd() - see addHairpin.
    function addTie(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "startTick", "endTick"]);
        if (bad) return { error: bad };
        try {
            var c = plainCursorAt(params.staff, params.startTick);
            curScore.selection.clear();
            var picked = 0;
            while (c.segment && c.tick < params.endTick) {
                var el = c.element;
                if (el && el.type === Element.CHORD) {
                    for (var i = 0; i < el.notes.length; i++) {
                        curScore.selection.select(el.notes[i], picked > 0);
                        picked++;
                    }
                }
                if (!c.next()) break;
            }
            if (picked === 0) throw new Error("no notes in range");
            cmd("tie");
            return { success: true, message: "Tie requested on " + picked + " note(s)" };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    // Moves the notes in the range into another voice using MuseScore's own "voice-N" command
    // (like Ctrl+Alt+2..4). Avoids driving a cursor on an empty voice track, which is what
    // corrupted the score state. Reading voices > 0 back is not supported by get_score.
    function moveToVoice(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "startTick", "endTick", "voice"]);
        if (bad) return { error: bad };
        if (params.voice < 0 || params.voice > 3) return { error: "voice must be 0-3" };
        try {
            var n = selectNotesAsList(params.staff, params.startTick, params.endTick, false);
            if (n === 0) throw new Error("no notes in range");
            cmd("voice-" + (params.voice + 1));
            return { success: true, message: "voice-" + (params.voice + 1) + " requested for " + n + " note(s)" };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    // measure numbers (1-based, inclusive) -> tick range, plus total measure count
    function measureRangeTicks(sm, em) {
        var m = curScore.firstMeasure, idx = 1, st = null, en = null;
        while (m) {
            if (idx === sm) st = m.firstSegment.tick;
            if (idx === em) en = m.firstSegment.tick + m.timesigActual.ticks;
            m = m.nextMeasure;
            idx++;
        }
        return { start: st, end: en, total: idx - 1 };
    }

    // Rewrites the pitches of EXISTING notes on one staff (voice 0), keeping rhythm, ties, dynamics and
    // articulations: used after copyMeasures to turn a copied line into a new part. params:
    //   staff, edits: [{ tick, pitch }] (single note) or [{ tick, pitches: [..] }] (same note count),
    //   flats (default false): spell black keys as flats instead of sharps.
    // Pitches are CONCERT pitch; the written spelling of a transposing instrument is kept by shifting
    // tpc2 by the same amount the existing note already had relative to tpc1.
    function setNotePitches(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff"]);
        if (bad) return { error: bad };
        if (!Array.isArray(params.edits) || params.edits.length === 0) return { error: "edits must be a non-empty array" };
        var sharpTpc = [14, 21, 16, 23, 18, 13, 20, 15, 22, 17, 24, 19];
        var flatTpc = [14, 9, 16, 11, 18, 13, 8, 15, 10, 17, 12, 19];
        var table = params.flats === true ? flatTpc : sharpTpc;
        var failed = [], done = 0;
        curScore.startCmd();
        try {
            for (var i = 0; i < params.edits.length; i++) {
                var ed = params.edits[i];
                var c = plainCursorAt(params.staff, ed.tick);
                var el = c.element;
                if (c.tick !== ed.tick || !el || el.type !== Element.CHORD) { failed.push(ed.tick + " (no chord)"); continue; }
                var want = ed.pitches !== undefined ? ed.pitches : [ed.pitch];
                if (!el.notes || el.notes.length !== want.length) { failed.push(ed.tick + " (" + (el.notes ? el.notes.length : 0) + " notes, expected " + want.length + ")"); continue; }
                for (var k = 0; k < want.length; k++) {
                    var n = el.notes[k];
                    var shift = n.tpc2 - n.tpc1;
                    n.pitch = want[k];
                    var t1 = table[((want[k] % 12) + 12) % 12];
                    n.tpc1 = t1;
                    n.tpc2 = t1 + shift;
                }
                done++;
            }
            curScore.endCmd();
            var out = { success: failed.length === 0, message: done + " chord(s) rewritten" };
            if (failed.length) out.failed = failed;
            return out;
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Show / hide a whole instrument (the eye icon in the Instruments panel) via Part.show.
    function setPartVisible(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "visible"]);
        if (bad) return { error: bad };
        curScore.startCmd();
        try {
            var st = curScore.staves[params.staff];
            if (!st || !st.part) throw new Error("staff " + params.staff + " not found");
            if (typeof curScore.setPartVisible !== "function") throw new Error("Score.setPartVisible is not available in this MuseScore build");
            curScore.setPartVisible(st.part, params.visible === true);
            curScore.endCmd();
            return { success: true, message: "Part '" + st.part.longName + "' visible=" + (params.visible === true) };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Sets a MuseScore style value by name (e.g. hideEmptyStaves=true) and reads it back.
    function setStyle(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["name", "value"]);
        if (bad) return { error: bad };
        curScore.startCmd();
        try {
            var before = curScore.style.value(params.name);
            curScore.style.setValue(params.name, params.value);
            var after = curScore.style.value(params.name);
            curScore.endCmd();
            return { success: true, message: "Style '" + params.name + "': " + before + " -> " + after, before: before, after: after };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Chord symbol (e.g. "Am7", "C/E") above the staff at a position.
    function addChordSymbol(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "tick", "text"]);
        if (bad) return { error: bad };
        curScore.startCmd();
        try {
            var c = plainCursorAt(params.staff, params.tick);
            // Insert first, set the text afterwards: setting the text of a Harmony that is not yet
            // part of the score (so it can't parse the chord against the score) crashed MuseScore.
            var h = newElement(Element.HARMONY);
            c.add(h);
            var added = c.segment && c.segment.annotations ? c.segment.annotations : [];
            var target = h;
            for (var i = added.length - 1; i >= 0; i--) {
                if (added[i].name === "Harmony") { target = added[i]; break; }
            }
            target.text = params.text;
            curScore.endCmd();
            return { success: true, message: "Chord symbol '" + params.text + "' added at tick " + c.tick };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Copies measures startMeasure..endMeasure (all staves, or firstStaff..lastStaff) and pastes
    // them starting at destMeasure, overwriting what is there. Runs the MuseScore actions outside
    // startCmd()/endCmd() (see addHairpin).
    function copyMeasures(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["startMeasure", "endMeasure", "destMeasure"]);
        if (bad) return { error: bad };
        try {
            var src = measureRangeTicks(params.startMeasure, params.endMeasure);
            var dst = measureRangeTicks(params.destMeasure, params.destMeasure);
            if (src.start === null || src.end === null || dst.start === null || params.startMeasure > params.endMeasure) throw new Error("invalid measure range (score has " + src.total + " measures)");
            var s0 = params.firstStaff !== undefined ? params.firstStaff : 0;
            var s1 = params.lastStaff !== undefined ? params.lastStaff + 1 : curScore.nstaves;
            // destStaff pastes onto another staff (the same number of staves, starting there).
            var d0 = params.destStaff !== undefined ? params.destStaff : s0;
            var d1 = d0 + (s1 - s0);
            if (d1 > curScore.nstaves) throw new Error("destStaff " + d0 + " leaves no room for " + (s1 - s0) + " staff/staves");
            curScore.selection.clear();
            curScore.selection.selectRange(src.start, src.end, s0, s1);
            cmd("copy");
            curScore.selection.clear();
            curScore.selection.selectRange(dst.start, dst.end, d0, d1);
            cmd("paste");
            return { success: true, message: "Measures " + params.startMeasure + "-" + params.endMeasure + " copied to " + params.destMeasure };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    // Transposes the notes in the range by a number of semitones (negative = down, max 24),
    // using MuseScore's own pitch-up / pitch-down actions so spelling stays sensible.
    function transpose(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "startTick", "endTick", "semitones"]);
        if (bad) return { error: bad };
        if (Math.abs(params.semitones) > 24 || params.semitones !== Math.floor(params.semitones)) return { error: "semitones must be an integer between -24 and 24" };
        try {
            var n = selectNotesAsList(params.staff, params.startTick, params.endTick, false);
            if (n === 0) throw new Error("no notes in range");
            var remaining = Math.abs(params.semitones);
            var up = params.semitones > 0;
            while (remaining >= 12) { cmd(up ? "pitch-up-octave" : "pitch-down-octave"); remaining -= 12; }
            while (remaining > 0) { cmd(up ? "pitch-up" : "pitch-down"); remaining--; }
            return { success: true, message: "Transposed " + n + " note(s) by " + params.semitones + " semitone(s)" };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    // Lists what a few well-known global enums/objects expose in THIS MuseScore build, so the
    // names used by other actions can be checked instead of guessed.
    function introspect(params) {
        var out = {};
        var probes = {
            Element: function () { return Element; },
            ClefType: function () { return ClefType; },
            BarLineType: function () { return BarLineType; },
            Segment: function () { return Segment; }
        };
        var wanted = Array.isArray(params.names) ? params.names : [];
        for (var i = 0; i < wanted.length; i++) {
            var n = wanted[i];
            try {
                if (!probes[n]) { out[n] = "unknown probe"; continue; }
                var o = probes[n]();
                var keys = [];
                for (var k in o) { if (typeof o[k] !== "function") keys.push(k + "=" + o[k]); }
                out[n] = keys.slice(0, 200);
            } catch (e) {
                out[n] = "not available (" + e + ")";
            }
        }
        // Property names of real objects. objects: [{type: "barline"|"measure"|"part"|"staff", measure?, staff?}]
        if (Array.isArray(params.scoreProps)) {
            var sv = {};
            for (var sp = 0; sp < params.scoreProps.length; sp++) { try { sv[params.scoreProps[sp]] = String(curScore[params.scoreProps[sp]]); } catch (e0) { sv[params.scoreProps[sp]] = "error"; } }
            out.score = sv;
        }
        if (params.selectAll === true) {
            cmd("select-all");
            var sel = curScore.selection.elements, names = {};
            for (var si = 0; sel && si < sel.length; si++) { var nm = sel[si].name + (sel[si].text !== undefined ? ":" + plainText(sel[si].text).slice(0, 30) : ""); if (/Text|Title|Composer|Lyricist|Subtitle/.test(nm)) names[nm] = (names[nm] || 0) + 1; }
            out.selectAllTexts = names;
        }
        var objs = Array.isArray(params.objects) ? params.objects : [];
        for (var j = 0; j < objs.length; j++) {
            var spec = objs[j], label = spec.type + ":" + (spec.measure !== undefined ? spec.measure : spec.staff), target = null;
            try {
                if (spec.type === "page") {
                    var pg0 = curScore.pages[spec.staff || 0];
                    var plist = [];
                    for (var pk0 in pg0) plist.push(pk0);
                    var elist = [];
                    var pels = pg0.elements;
                    if (pels) { for (var q = 0; q < pels.length && q < 40; q++) elist.push((pels[q] ? pels[q].name + ":" + plainText(pels[q].text) : "null")); }
                    out["page:" + (spec.staff || 0)] = { properties: plist.slice(0, 60), elements: elist };
                    continue;
                }
                if (spec.type === "part") target = curScore.staves[spec.staff].part;
                else if (spec.type === "staff") target = curScore.staves[spec.staff];
                else {
                    var m = curScore.firstMeasure, idx = 1;
                    while (m && idx < spec.measure) { m = m.nextMeasure; idx++; }
                    if (!m) throw new Error("measure not found");
                    if (spec.type === "measure") target = m;
                    else {
                        var cand = m.firstSegment, bl = null;
                        while (cand) {
                            var el = cand.elementAt ? cand.elementAt(0) : null;
                            if (el && el.name === "BarLine") bl = el;
                            cand = cand.nextInMeasure;
                        }
                        target = bl;
                    }
                }
                var props = [];
                if (target && Array.isArray(spec.props)) {
                    for (var pi = 0; pi < spec.props.length; pi++) { var pn = spec.props[pi]; props.push(pn + ": " + (pn in target ? typeof target[pn] + " = " + target[pn] : "ABSENT")); }
                } else if (target) { for (var pk in target) props.push(pk + (typeof target[pk] === "function" ? "()" : "=" + target[pk])); }
                out[label] = target ? props.slice(0, 160) : "not found";
            } catch (e2) {
                out[label] = "error: " + e2;
            }
        }
        return { success: true, message: "introspection", info: out };
    }

    // Barline at the END of a measure (1-based): normal | double | final | repeat-end. For
    // "repeat-start" the barline at the START of that measure is changed instead.
    function setBarline(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["measure", "type"]);
        if (bad) return { error: bad };
        var names = { "normal": "NORMAL", "double": "DOUBLE", "repeat-start": "START_REPEAT", "repeat-end": "END_REPEAT", "final": "END" };
        if (names[params.type] === undefined) return { error: "type must be one of: " + Object.keys(names).join(", ") };
        curScore.startCmd();
        try {
            var m = curScore.firstMeasure, idx = 1;
            while (m && idx < params.measure) { m = m.nextMeasure; idx++; }
            if (!m) throw new Error("measure " + params.measure + " not found");
            var value = BarLineType[names[params.type]];
            if (value === undefined) throw new Error("BarLineType." + names[params.type] + " not available");
            var wantStart = params.type === "repeat-start";
            var bl = null;
            var cand = m.firstSegment;
            while (cand) {
                var el = cand.elementAt ? cand.elementAt(0) : null;
                if (el && el.name === "BarLine") {
                    if (wantStart) { bl = el; break; }
                    bl = el;
                }
                cand = cand.nextInMeasure;
            }
            if (!bl) throw new Error("no barline element found in measure " + params.measure);
            // The property is `barlineType` (lowercase l) in this build. Assigning to a name that
            // does not exist is silently accepted and even reads back, so only names that really
            // exist on the element are tried.
            var tried = [], used = null;
            var candidates = ["barlineType", "barLineType", "subtype"];
            for (var i = 0; i < candidates.length && !used; i++) {
                if (!(candidates[i] in bl)) { tried.push(candidates[i] + "(absent)"); continue; }
                try { bl[candidates[i]] = value; } catch (e1) { }
                tried.push(candidates[i] + "=" + bl[candidates[i]]);
                if (bl[candidates[i]] === value) used = candidates[i];
            }
            if (!used) {
                // The barline property refuses repeat types (they are measure-level in the engine).
                // Dropping a new BAR_LINE element on the measure crashed MuseScore, so use the
                // measure's own repeat flags instead, when this build exposes them.
                var flag = params.type === "repeat-start" ? "repeatStart" : (params.type === "repeat-end" ? "repeatEnd" : null);
                if (flag && (flag in m)) {
                    m[flag] = true;
                    if (m[flag] === true) {
                        curScore.endCmd();
                        return { success: true, message: "Measure " + params.measure + " " + flag + "=true" };
                    }
                }
                var related = [];
                for (var k in m) { if (/repeat/i.test(k)) related.push("measure." + k); }
                for (var k2 in bl) { if (/bar|type|repeat/i.test(k2)) related.push(k2); }
                throw new Error("barline type did not stick (tried " + tried.join(", ") + "); related properties: " + related.join(", "));
            }
            curScore.endCmd();
            return { success: true, message: "Barline '" + params.type + "' set on measure " + params.measure + " via " + used };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Clef change at a position on a staff. clef: treble | bass | alto | tenor | treble8vb | percussion
    function addClef(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "tick", "clef"]);
        if (bad) return { error: bad };
        var enumNames = { treble: "G", bass: "F", alto: "C3", tenor: "C4", treble8vb: "G8_VB", percussion: "PERC" };
        if (!enumNames[params.clef]) return { error: "clef must be one of: " + Object.keys(enumNames).join(", ") };
        curScore.startCmd();
        try {
            if (typeof ClefType === "undefined" || ClefType[enumNames[params.clef]] === undefined) {
                throw new Error("ClefType." + enumNames[params.clef] + " is not available in this MuseScore build (see introspect)");
            }
            var c = plainCursorAt(params.staff, params.tick);
            var clef = newElement(Element.CLEF);
            clef.concertClefType = ClefType[enumNames[params.clef]];
            clef.transposingClefType = ClefType[enumNames[params.clef]];
            c.add(clef);
            curScore.endCmd();
            return { success: true, message: "Clef '" + params.clef + "' added at tick " + c.tick + " on staff " + params.staff };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    function exportAllowed(path, format) {
        var formats = ["pdf", "mid", "musicxml", "mxl", "png", "wav", "mp3", "flac", "ogg"];
        if (formats.indexOf(format) < 0) return "format must be one of: " + formats.join(", ");
        if (typeof path !== "string" || path.charAt(0) !== "/" || path.indexOf("..") >= 0) return "path must be absolute and without '..'";
        return null;
    }

    // Exports the whole score. path: absolute path WITHOUT extension; format: pdf|mid|musicxml|mxl|png|wav|mp3|flac|ogg (audio uses MuseScore's own sounds)
    function exportScore(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["path", "format"]);
        if (bad) return { error: bad };
        var deny = exportAllowed(params.path, params.format);
        if (deny) return { error: deny };
        try {
            var ok = writeScore(curScore, params.path, params.format);
            return ok ? { success: true, message: "Exported to " + params.path + "." + params.format } : { error: "writeScore returned false for " + params.path + "." + params.format };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    // Exports every already-created part (excerpt) as its own file: <directory>/<partName>.<format>
    function exportParts(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["directory", "format"]);
        if (bad) return { error: bad };
        var deny = exportAllowed(params.directory + "/x", params.format);
        if (deny) return { error: deny };
        try {
            var ex = curScore.excerpts;
            if (!ex || ex.length === 0) throw new Error("this score has no parts (excerpts) yet - create them in MuseScore first (Parts dialog)");
            var done = [], failed = [];
            for (var i = 0; i < ex.length; i++) {
                var name = String(ex[i].title || ("part" + (i + 1))).replace(/[^A-Za-z0-9 _-]/g, "_");
                var ok = writeScore(ex[i].partScore, params.directory + "/" + name, params.format);
                (ok ? done : failed).push(name);
            }
            return failed.length ? { error: "exported " + done.length + ", failed: " + failed.join(", ") } : { success: true, message: "Exported " + done.length + " part(s) to " + params.directory, parts: done };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    // Saves the open score in place (same as File > Save). An untitled score would open a dialog.
    function saveScore(params) {
        if (!curScore) return { error: "No score open" };
        try {
            cmd("file-save");
            return { success: true, message: "Save requested for the open score" };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    function plainText(t) {
        return String(t === undefined || t === null ? "" : t).replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").replace(/\s+/g, " ").trim();
    }

    // Adds title / subtitle / composer / lyricist text in the score's title frame. The API can
    // only ADD a text: it cannot reach an existing frame text to replace it, and adding one over
    // an existing text overlaps the two. So this refuses when a text of that kind already exists -
    // edit that one by hand in MuseScore. Useful for scores that have no title frame text yet.
    function setScoreText(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["kind", "text"]);
        if (bad) return { error: bad };
        var kinds = ["title", "subtitle", "composer", "lyricist", "parttitle"];
        if (kinds.indexOf(params.kind) < 0) return { error: "kind must be one of: " + kinds.join(", ") };
        var current = (params.kind === "title" || params.kind === "composer" || params.kind === "lyricist") ? curScore[params.kind] : "";
        if (current) return { error: "a " + params.kind + " text already exists ('" + current + "') and the API cannot replace it - edit it in MuseScore" };
        curScore.startCmd();
        try {
            if (typeof curScore.addText !== "function") throw new Error("Score.addText is not available in this MuseScore build");
            curScore.addText(params.kind, params.text);
            curScore.endCmd();
            return { success: true, message: params.kind + " added: '" + params.text + "'" };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Navigation markers (segno, coda, to-coda, fine) on a measure.
    function addMarker(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["measure", "kind"]);
        if (bad) return { error: bad };
        // markerType values: SEGNO=0, CODA=2, FINE=5, TOCODA=6; label is what jumps refer to.
        var presets = { segno: [0, "segno"], coda: [2, "codab"], tocoda: [6, "coda"], fine: [5, "fine"] };
        if (!presets[params.kind]) return { error: "kind must be one of: " + Object.keys(presets).join(", ") };
        curScore.startCmd();
        try {
            var r = measureRangeTicks(params.measure, params.measure);
            if (r.start === null) throw new Error("measure " + params.measure + " not found");
            var mk = newElement(Element.MARKER);
            mk.markerType = presets[params.kind][0];
            mk.label = presets[params.kind][1];
            var c = plainCursorAt(0, r.start);
            c.add(mk);
            curScore.endCmd();
            return { success: true, message: "Marker '" + params.kind + "' added on measure " + params.measure };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Jump instructions (D.C., D.S., ...) on a measure.
    function addJump(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["measure", "kind"]);
        if (bad) return { error: bad };
        var presets = {
            "dc": ["D.C.", "start", "end", ""],
            "dc-al-fine": ["D.C. al Fine", "start", "fine", ""],
            "dc-al-coda": ["D.C. al Coda", "start", "coda", "codab"],
            "ds": ["D.S.", "segno", "end", ""],
            "ds-al-fine": ["D.S. al Fine", "segno", "fine", ""],
            "ds-al-coda": ["D.S. al Coda", "segno", "coda", "codab"]
        };
        if (!presets[params.kind]) return { error: "kind must be one of: " + Object.keys(presets).join(", ") };
        curScore.startCmd();
        try {
            var r = measureRangeTicks(params.measure, params.measure);
            if (r.start === null) throw new Error("measure " + params.measure + " not found");
            var j = newElement(Element.JUMP);
            j.text = presets[params.kind][0];
            j.jumpTo = presets[params.kind][1];
            j.playUntil = presets[params.kind][2];
            j.continueAt = presets[params.kind][3];
            var c = plainCursorAt(0, r.start);
            c.add(j);
            curScore.endCmd();
            return { success: true, message: "Jump '" + params.kind + "' added on measure " + params.measure };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Deletes whole measures (1-based, inclusive) from every staff, shifting the rest left.
    // "time-delete" is a structural command that manages its own undo step: it crashed MuseScore
    // when called inside this plugin's startCmd()/endCmd(), so it runs outside of one.
    function deleteMeasures(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["startMeasure", "endMeasure"]);
        if (bad) return { error: bad };
        try {
            var m = curScore.firstMeasure, idx = 1, startTick = null, endTick = null;
            while (m) {
                if (idx === params.startMeasure) startTick = m.firstSegment.tick;
                if (idx === params.endMeasure) endTick = m.firstSegment.tick + m.timesigActual.ticks;
                m = m.nextMeasure;
                idx++;
            }
            var total = idx - 1;
            if (startTick === null || endTick === null || params.startMeasure > params.endMeasure) throw new Error("invalid measure range (score has " + total + " measures)");
            if (params.startMeasure === 1 && params.endMeasure === total) throw new Error("refusing to delete every measure");
            curScore.selection.clear();
            curScore.selection.selectRange(startTick, endTick, 0, curScore.nstaves);
            cmd("time-delete");
            return { success: true, message: "Deletion of measures " + params.startMeasure + "-" + params.endMeasure + " requested (score had " + total + ")" };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    // Removes a whole instrument (part) including ALL of its staves, via Score.removeParts.
    // partName must match the part's long name exactly, as a guard against removing the wrong one.
    function removePart(params) {
        if (!curScore) return { error: "No score open" };
        var bad = needNumbers(params, ["staff", "partName"]);
        if (bad) return { error: bad };
        curScore.startCmd();
        try {
            var st = curScore.staves[params.staff];
            if (!st || !st.part) throw new Error("staff " + params.staff + " not found");
            if (st.part.longName !== params.partName) throw new Error("partName mismatch: staff " + params.staff + " belongs to '" + st.part.longName + "'");
            if (curScore.parts.length <= 1) throw new Error("refusing to remove the only part");
            if (typeof curScore.removeParts !== "function") throw new Error("Score.removeParts is not available in this MuseScore build");
            var before = curScore.nstaves;
            curScore.removeParts([st.part]);
            curScore.endCmd();
            return { success: true, message: "Part '" + params.partName + "' removal requested (staves " + before + " -> " + curScore.nstaves + ")" };
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // Init
    onRun: {
        console.log("Starting MuseScore API Server on port 8765");
        
        // Start the WebSocket server
        api.websocketserver.listen(8765, function(clientId) {
            console.log("Client connected with ID: " + clientId);
            clientConnections.push(clientId);
            
            // Set up message handler for this client
            api.websocketserver.onMessage(clientId, function(message) {
                processMessage(message, clientId);
            });
        });
    
        // Initialize cursor state for any open score

        if (curScore) {
            initCursorState();
        }

    }
}
