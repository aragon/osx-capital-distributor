#!/usr/bin/env bun

/**
 * CSV → JSON converter for DirectAllocationStrategy allocations.
 *
 * Usage:
 *   bun run script/utils/convertDirectAllocations.ts <csvPath> [skipHeader=true]
 *
 * Input CSV format (comma separated, no quotes):
 *   0xRecipientAddress,amountInWei
 *   Lines starting with "#" or ";" are ignored as comments.
 *
 * Output (printed to stdout):
 *   {
 *     "recipients": ["0x...", ...],
 *     "amounts": ["1000000000000000000", ...]
 *   }
 */

import { readFileSync } from "fs";
import { resolve } from "path";

const [, , rawPath, skipHeaderArg] = process.argv;

if (!rawPath) {
  console.error("Usage: bun run script/utils/convertDirectAllocations.ts <csvPath> [skipHeader=true]");
  process.exit(1);
}

const csvPath = resolve(rawPath);
let shouldSkipHeader = skipHeaderArg !== "false";

let fileContents: string;
try {
  fileContents = readFileSync(csvPath, "utf8");
} catch (error) {
  console.error(`Failed to read CSV file at ${csvPath}:`, error);
  process.exit(1);
}

const lines = fileContents.split(/\r?\n/);
const recipients: string[] = [];
const amounts: string[] = [];

const addressPattern = /^0x[a-fA-F0-9]{40}$/;
const isComment = (value: string) => value.startsWith("#") || value.startsWith(";");

for (let i = 0; i < lines.length; i++) {
  const rawLine = lines[i].trim();
  if (rawLine.length === 0 || isComment(rawLine)) {
    continue;
  }

  if (shouldSkipHeader) {
    shouldSkipHeader = false;
    continue;
  }

  const parts = rawLine.split(",");
  if (parts.length !== 2) {
    console.error(`Invalid row on line ${i + 1}: expected "address,amount"`);
    process.exit(1);
  }

  const recipient = parts[0].trim();
  const amount = parts[1].trim();

  if (!addressPattern.test(recipient)) {
    console.error(`Invalid address on line ${i + 1}: ${recipient}`);
    process.exit(1);
  }

  if (!/^[0-9]+$/.test(amount)) {
    console.error(`Invalid amount on line ${i + 1}: ${amount}`);
    process.exit(1);
  }

  recipients.push(recipient);
  amounts.push(amount);
}

const payload = {
  recipients,
  amounts,
};

process.stdout.write(JSON.stringify(payload));
