// 프로토타입(prototype/trail-grade-field.html)의 코스 처리 함수를 그대로 꺼내 Node에서 실행합니다.
// Python 변환기가 같은 결과를 내는지 비교하는 기준값을 만듭니다 (tests/test_parity.py).
//
// 입력(stdin, JSON): {"sample": true} 또는 {"pts": [[lat, lon, ele], ...]}
//                    + {"interval": 20, "smooth": 100, "minClimb": 20}
// 출력(stdout, JSON): {name, pts?, N, total, ele, segs: [...]}
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, "..", "prototype", "trail-grade-field.html"), "utf8");

function grabFunction(name) {
  const start = html.indexOf("function " + name + "(");
  if (start < 0) throw new Error("프로토타입에서 함수를 찾지 못했습니다: " + name);
  let depth = 0;
  for (let k = html.indexOf("{", start); k < html.length; k++) {
    if (html[k] === "{") depth++;
    else if (html[k] === "}" && --depth === 0) return html.slice(start, k + 1);
  }
  throw new Error("함수 끝을 찾지 못했습니다: " + name);
}

function grabLine(prefix) {
  const line = html.split("\n").find((l) => l.startsWith(prefix));
  if (!line) throw new Error("프로토타입에서 줄을 찾지 못했습니다: " + prefix);
  return line;
}

const FUNCS = ["mulberry32", "clamp", "haversine", "movingAvg", "makeSample", "buildCourse",
  "zigzag", "findPlateaus", "trimPiece", "mergeSame", "maxWin", "segment"];
const code = [grabLine("var FLAT_GRADE="), grabLine("var R_E="), ...FUNCS.map(grabFunction),
  "result = { makeSample, buildCourse };"].join("\n");
const ctx = { result: null };
vm.runInNewContext(code, ctx);
const { makeSample, buildCourse } = ctx.result;

const input = JSON.parse(readFileSync(0, "utf8"));
const params = { interval: input.interval ?? 20, smooth: input.smooth ?? 100, minClimb: input.minClimb ?? 20 };
let pts, name;
if (input.sample) {
  const s = makeSample();
  pts = s.pts.map((p) => [p.lat, p.lon, p.ele]);
  name = s.name;
} else {
  pts = input.pts;
}
const c = buildCourse(pts.map(([lat, lon, ele]) => ({ lat, lon, ele })), params);
const out = {
  name,
  N: c.N,
  total: c.total,
  ele: Array.from(c.ele),
  gain: c.asc[c.N - 1],
  segs: c.segs.map((s) => ({
    type: s.type, s: s.s, e: s.e, len: s.len, dEle: s.dEle, gain: s.gain, loss: s.loss,
    avg: s.avg, max: s.max, hi: s.hi, lo: s.lo, no: s.no,
  })),
};
if (input.sample) out.pts = pts;
process.stdout.write(JSON.stringify(out));
