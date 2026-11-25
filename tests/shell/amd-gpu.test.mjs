import { test, expect } from 'bun:test';
import { readFileSync, mkdirSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

const src = readFileSync(new URL('../../shell/services/SystemStats.qml', import.meta.url), 'utf8');
const script = eval(/"sh", "-c", (`[\s\S]*?`)\]/.exec(src)[1]);

function sample(state) {
  const root = mkdtempSync(tmpdir() + '/amd-');
  const dev = `${root}/drm/card1/device`;
  mkdirSync(`${dev}/hwmon/hwmon3`, { recursive: true }); mkdirSync(`${dev}/power`);
  writeFileSync(`${dev}/gpu_busy_percent`, '37\n');
  writeFileSync(`${dev}/mem_info_vram_used`, String(2 * 1048576 * 1024) + '\n');
  writeFileSync(`${dev}/mem_info_vram_total`, String(8 * 1048576 * 1024) + '\n');
  writeFileSync(`${dev}/power/runtime_status`, state + '\n');
  writeFileSync(`${dev}/hwmon/hwmon3/power1_average`, '45000000\n');
  writeFileSync(`${dev}/hwmon/hwmon3/temp1_input`, '61000\n');
  const fake = script.replaceAll('/sys/class/drm', `${root}/drm`).replaceAll('/sys/bus/pci/drivers/nvidia', `${root}/none`).replace('sleep 2', 'exit 0');
  return spawnSync('sh', ['-c', fake], { encoding: 'utf8' }).stdout;
}

test('an awake AMD GPU reports use, VRAM, power and temperature', () => {
  const out = sample('active');
  expect(out).toContain('gpustate active');
  expect(out).toContain('gpu 37, 2048, 8192, 45');
  expect(out).toContain('gputemp 61000');
});
test('a sleeping AMD GPU is not woken to be read', () => {
  const out = sample('suspended');
  expect(out).toContain('gpustate suspended');
  expect(out).not.toContain('gpu 37');
});
