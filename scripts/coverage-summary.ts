// Coverage summary reporter — reads kcov JSON outputs and prints a table.
// Usage: COVERAGE_NAMES="mod1 mod2 merged" deno run --allow-read --allow-env coverage-summary.ts

function findCoverageJson(dir: string): string | null {
  // Try known paths first
  for (const sub of ["kcov-merged/coverage.json", "coverage.json"]) {
    try {
      return Deno.readTextFileSync(`${dir}/${sub}`);
    } catch {
      continue;
    }
  }
  // Fallback: search for test.<hash>/coverage.json (single-binary kcov output)
  try {
    for (const entry of Deno.readDirSync(dir)) {
      if (entry.isDirectory && entry.name.startsWith("test.")) {
        try {
          return Deno.readTextFileSync(`${dir}/${entry.name}/coverage.json`);
        } catch {
          continue;
        }
      }
    }
  } catch { /* dir doesn't exist */ }
  return null;
}

const names = (Deno.env.get("COVERAGE_NAMES") ?? "").trim().split(/ +/);
for (const name of names) {
  const json = findCoverageJson(`coverage/${name}`);
  if (json) {
    const d = JSON.parse(json);
    console.log(
      `${name.padEnd(25)} ${d.percent_covered.padStart(6)}%  (${d.covered_lines}/${d.total_lines} lines)`,
    );
  } else {
    console.log(`${name.padEnd(25)}   N/A`);
  }
}
