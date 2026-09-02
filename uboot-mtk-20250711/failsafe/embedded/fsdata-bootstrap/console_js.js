/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2026 Yuzhii0718
 *
 * All rights reserved.
 *
 * This file is part of the project bl-mt798x-dhcpd
 * You may not use, copy, modify or distribute this file except in compliance with the license agreement.
 */

function consoleInit() {
    const outputElement = document.getElementById("console_out");
    const commandInput = document.getElementById("console_cmd");
    const statusElement = document.getElementById("console_status");
    const tokenInput = document.getElementById("console_token");
    const abortButton = document.getElementById("console_abort");
    const persistKey = "failsafe_console_output";
    const persistMax = 200000;

    APP_STATE.console = APP_STATE.console || {
        running: false,
        pollTimer: null,
        history: [],
        histPos: -1,
        tokenKey: "failsafe_console_token",
        busySince: 0
    };

    /*
     * Repetition period of the poll loop.
     *
     * While a command is executing we poll twice as fast: net commands
     * (tftp, ping, ...) stream their progress through the very same
     * endpoint, and 300 ms makes a '#' progress bar look stuttery.
     */
    function pollDelay() {
        return APP_STATE.console.busySince ? 150 : 300;
    }

    /*
     * Reflect the server-side "busy" flag in the status line.
     *
     * Without this a long-running command looks like a hung page: the
     * fetch for /console/exec stays pending for the whole transfer and
     * nothing on screen changes until it completes.
     */
    function setBusy(busy) {
        if (busy) {
            if (!APP_STATE.console.busySince) APP_STATE.console.busySince = Date.now();
            const seconds = Math.floor((Date.now() - APP_STATE.console.busySince) / 1000);
            abortButton && (abortButton.style.display = "");
            setStatus(t("console.status.running") + " · " + seconds + "s");
            return;
        }
        if (APP_STATE.console.busySince) {
            APP_STATE.console.busySince = 0;
            abortButton && (abortButton.style.display = "none");
            setStatus(t("console.status.done"));
        }
    }

    function loadToken() {
        try {
            const storedToken = localStorage.getItem(APP_STATE.console.tokenKey);
            tokenInput && storedToken && (tokenInput.value = storedToken);
        } catch (error) { }
    }

    function saveToken() {
        try {
            tokenInput && localStorage.setItem(APP_STATE.console.tokenKey, tokenInput.value || "");
        } catch (error) { }
    }

    function setStatus(message) {
        statusElement && (statusElement.textContent = message || "");
    }

    function loadPersistedOutput() {
        if (!outputElement) return;
        try {
            const savedOutput = sessionStorage.getItem(persistKey);
            if (savedOutput) outputElement.textContent = savedOutput;
        } catch (error) { }
    }

    function savePersistedOutput() {
        if (!outputElement) return;
        try {
            let currentOutput = outputElement.textContent || "";
            if (currentOutput.length > persistMax) currentOutput = currentOutput.slice(currentOutput.length - persistMax);
            sessionStorage.setItem(persistKey, currentOutput);
        } catch (error) { }
    }

    /*
     * Append console output with terminal semantics.
     *
     * U-Boot progress output (tftp's '#' marks, mtkupgrade's percentage
     * bars, "Loading: *\b", ...) is written with \r (return to column 0)
     * and \b (backspace) so a single line keeps repainting itself.
     *
     * Rewriting every \r to \n — as done previously — turned one progress
     * bar into hundreds of lines and destroyed the whole point of the
     * in-place update.  We interpret the control characters instead:
     *
     *   \r      discard the current line and continue from column 0
     *   \r\n    a real newline (the \n does the work, \r is skipped)
     *   \b      drop the last character
     */
    function appendText(text) {
        if (!outputElement) return;
        if (!text) return;

        let current = outputElement.textContent || "";
        let pending = "";

        function flush() {
            if (pending) {
                current += pending;
                pending = "";
            }
        }

        for (let index = 0; index < text.length; index++) {
            const character = text[index];

            if (character === "\r") {
                flush();
                /* "\r\n" is a plain newline: let the \n handle it */
                if (text[index + 1] !== "\n") {
                    const lastBreak = current.lastIndexOf("\n");
                    current = lastBreak < 0 ? "" : current.slice(0, lastBreak + 1);
                }
                continue;
            }

            if (character === "\b") {
                flush();
                if (current && current[current.length - 1] !== "\n") {
                    current = current.slice(0, -1);
                }
                continue;
            }

            if (character === "\n") {
                flush();
                current += "\n";
                continue;
            }

            pending += character;
        }
        flush();

        if (current.length > persistMax) current = current.slice(current.length - persistMax);
        outputElement.textContent = current;
        savePersistedOutput();
        outputElement.scrollTop = outputElement.scrollHeight;
    }

    async function pollOnce() {
        if (!APP_STATE.console.running) return;
        try {
            const formData = new FormData();
            if (tokenInput && tokenInput.value) formData.append("token", tokenInput.value);
            const response = await fetch("/console/poll", { method: "POST", body: formData });
            if (!response.ok) {
                setStatus(t("console.status.http") + " " + response.status);
                return;
            }
            const responseText = await response.text();
            let payload;
            try {
                payload = JSON.parse(responseText);
            } catch (error) {
                setStatus(t("console.status.parse"));
                return;
            }
            payload && payload.data && appendText(payload.data);
            setBusy(!!(payload && payload.busy));
            if (payload && payload.overflow) {
                setStatus(String.fromCodePoint(0x26A0) + " " + t("console.status.overflow"));
            }
        } catch (error) {
            setStatus(t("console.status.error") + " " + (error && error.message ? error.message : String(error)));
        }
    }

    function schedulePoll() {
        if (APP_STATE.console.pollTimer) clearTimeout(APP_STATE.console.pollTimer);
        APP_STATE.console.pollTimer = setTimeout(async () => {
            await pollOnce();
            schedulePoll();
        }, pollDelay());
    }

    window.consoleSend = async function () {
        if (!commandInput || !commandInput.value) return;
        saveToken();
        const commandLine = String(commandInput.value);
        commandInput.value = "";
        APP_STATE.console.history.unshift(commandLine);
        APP_STATE.console.history.length > 50 && (APP_STATE.console.history.length = 50);
        APP_STATE.console.histPos = -1;

        try {
            const formData = new FormData();
            formData.append("cmd", commandLine);
            if (tokenInput && tokenInput.value) formData.append("token", tokenInput.value);
            /*
             * Mark busy before the request goes out: the response only
             * arrives once run_command() has finished, which for a
             * network command can be minutes.  The live output is
             * delivered by the poll loop in the meantime.
             */
            setBusy(true);
            const response = await fetch("/console/exec", { method: "POST", body: formData });
            const responseText = await response.text();
            if (!response.ok) {
                APP_STATE.console.busySince = 0;
                abortButton && (abortButton.style.display = "none");
                setStatus(t("console.status.http") + " " + response.status + (responseText ? ": " + responseText : ""));
                return;
            }
            try {
                const payload = JSON.parse(responseText);
                APP_STATE.console.busySince = 0;
                abortButton && (abortButton.style.display = "none");
                setStatus(t("console.status.ret") + " " + (payload && typeof payload.ret !== "undefined" ? payload.ret : "?"));
            } catch (error) {
                APP_STATE.console.busySince = 0;
                abortButton && (abortButton.style.display = "none");
                setStatus(t("console.status.done"));
            }
        } catch (error) {
            setStatus(t("console.status.error") + " " + (error && error.message ? error.message : String(error)));
        }
    };

    /*
     * Request the server to interrupt the running command.
     *
     * Network commands spend their time in net_loop(); the POST is served
     * from inside that very loop and makes it exit, mirroring Ctrl+C on a
     * serial console.  It is safe to repeat while a command is running.
     */
    window.consoleAbort = async function () {
        if (!APP_STATE.console.busySince) return;
        const formData = new FormData();
        if (tokenInput && tokenInput.value) formData.append("token", tokenInput.value);
        try {
            const response = await fetch("/console/abort", { method: "POST", body: formData });
            const responseText = await response.text();
            if (!response.ok) {
                setStatus(t("console.status.http") + " " + response.status + (responseText ? ": " + responseText : ""));
            }
        } catch (error) {
            setStatus(t("console.status.error") + " " + (error && error.message ? error.message : String(error)));
        }
    };

    window.consoleClear = async function () {
        saveToken();
        try {
            const formData = new FormData();
            if (tokenInput && tokenInput.value) formData.append("token", tokenInput.value);
            const response = await fetch("/console/clear", { method: "POST", body: formData });
            if (response.ok) {
                outputElement && (outputElement.textContent = "");
                try { sessionStorage.removeItem(persistKey); } catch (error) { }
                setStatus(t("console.status.cleared"));
            } else {
                setStatus(t("console.status.http") + " " + response.status);
            }
        } catch (error) {
            setStatus(t("console.status.error") + " " + (error && error.message ? error.message : String(error)));
        }
    };

    if (commandInput) {
        commandInput.addEventListener("keydown", function (event) {
            if (event.ctrlKey && (event.key === "c" || event.key === "C")) {
                /*
                 * While a command is running Ctrl+C aborts it (like a
                 * serial console); otherwise it is the ordinary copy
                 * shortcut and must be left to the browser.
                 */
                if (APP_STATE.console.busySince) {
                    event.preventDefault();
                    window.consoleAbort();
                }
                return;
            }
            if (event.key === "Enter") {
                event.preventDefault();
                window.consoleSend();
                return;
            }
            if (event.key === "ArrowUp") {
                const historyEntries = APP_STATE.console.history;
                if (!historyEntries || !historyEntries.length) return;
                APP_STATE.console.histPos = Math.min(historyEntries.length - 1, APP_STATE.console.histPos + 1);
                commandInput.value = historyEntries[APP_STATE.console.histPos] || "";
                event.preventDefault();
                return;
            }
            if (event.key === "ArrowDown") {
                const historyEntriesDown = APP_STATE.console.history;
                if (!historyEntriesDown || !historyEntriesDown.length) return;
                APP_STATE.console.histPos = Math.max(-1, APP_STATE.console.histPos - 1);
                commandInput.value = APP_STATE.console.histPos >= 0 ? (historyEntriesDown[APP_STATE.console.histPos] || "") : "";
                event.preventDefault();
            }
        });
    }

    APP_STATE.console.running = true;
    loadToken();
    loadPersistedOutput();
    setStatus(t("console.status.ready"));
    schedulePoll();
}
