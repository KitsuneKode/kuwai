import { useRef, type CSSProperties } from 'react'
import { Bar, Button, Check, Roll, Spinner, Stage, type Act } from '../../kit'
import { ArrowUp, Package } from 'lucide-react'
import './island.css'

// kuwai's island telling one update story, every state in one loop:
// rest (the count) → the banner grows down → Review morphs it into the panel
// (loading: a skeleton at the rows' own geometry) → rows resolve top to
// bottom, the AUR row fails *on itself* with Retry → fixed → Update folds the
// panel into a progress notch → success → back to rest; a new check buds the
// count back in, so the loop meets itself.
//
// One black shape whose box springs between presentations (grow: ~3%
// overshoot; shrink: critically damped, a beat late so content has cleared).
// Content is a separate layer at its final positions: nothing stretches.
// Real strings: the count, "3 updates available", Review, the three
// packages, the error, Retry, Update, Updating, Up to date. The desktop below
// is filler.

function spring(zeta: number, omega: number, ms: number, n = 48) {
  const wd = omega * Math.sqrt(1 - zeta * zeta)
  const pts: string[] = []
  for (let i = 0; i <= n; i++) {
    const t = (i / n) * (ms / 1000)
    const x = i === n ? 1 : 1 - Math.exp(-zeta * omega * t) * (Math.cos(wd * t) + ((zeta * omega) / wd) * Math.sin(wd * t))
    pts.push(x.toFixed(4))
  }
  return `linear(${pts.join(', ')})`
}
const GROW = { ease: spring(0.74, 15, 520), ms: 520 }
const SHRINK = { ease: spring(0.99, 20, 380), ms: 380 }

type Mode = 'rest' | 'banner' | 'panel' | 'progress' | 'done'
type Box = { w: number; h: number; r: number }
const GEO: Record<Mode, Box> = {
  rest: { w: 236, h: 34, r: 17 },
  banner: { w: 440, h: 84, r: 26 },
  panel: { w: 560, h: 316, r: 28 },
  progress: { w: 300, h: 40, r: 20 },
  done: { w: 236, h: 40, r: 20 },
}
const SIZE: Record<Mode, number> = { rest: 0, done: 1, progress: 2, banner: 3, panel: 4 }

type RowState = 'skeleton' | 'ready' | 'error' | 'retrying'
type S = {
  mode: Mode
  count: number
  chip: boolean
  rows: RowState[]
  pct: number
  step: number
  canUpdate: boolean
}
const START: S = { mode: 'rest', count: 3, chip: true, rows: ['skeleton', 'skeleton', 'skeleton'], pct: 0, step: 0, canUpdate: false }
const POSTER: S = { ...START, mode: 'panel', rows: ['ready', 'ready', 'error'] }

const PKGS = [
  { name: 'linux', from: '6.17.7', to: '6.17.8', src: 'Arch' },
  { name: 'firefox', from: '145.0', to: '145.0.1', src: 'Arch' },
  { name: 'paru-bin', from: '2.1.0', to: '2.1.1', src: 'AUR' },
]

function Ring({ p }: { p: number }) {
  return (
    <svg viewBox="0 0 20 20" width="18" height="18" className="kw-ring" aria-hidden>
      <circle cx="10" cy="10" r="8" className="kw-ring__track" />
      <circle cx="10" cy="10" r="8" className="kw-ring__arc" pathLength={1} style={{ strokeDashoffset: 1 - p }} />
    </svg>
  )
}

function PkgRow({ i, st }: { i: number; st: RowState }) {
  const p = PKGS[i]
  const skel = st === 'skeleton'
  const bad = st === 'error' || st === 'retrying'
  return (
    <div className="kw-row" data-skel={skel || undefined} data-bad={bad || undefined}>
      <span className="kw-row__tile"><span className="kw-fade" data-on={!skel || undefined}><Package size={16} strokeWidth={2} /></span></span>
      <span className="kw-row__words">
        <span className="kw-row__title">{skel ? <Bar w={[64, 72, 80][i]} h={7} tone={3} /> : p.name}</span>
        <span className="kw-row__sub">
          <span className="kw-stack">
            <span className="kw-fade" data-on={skel || undefined}><Bar w={[96, 84, 104][i]} h={6} tone={2} /></span>
            <span className="kw-fade kw-row__err" data-on={bad || undefined}>Couldn’t reach the AUR</span>
            <span className="kw-fade" data-on={st === 'ready' || undefined}>{p.from} → {p.to}</span>
          </span>
        </span>
      </span>
      {/* Every trailing state stays mounted in one cell and crossfades: nothing pops */}
      <span className="kw-row__end">
        <span className="kw-fade" data-on={skel || undefined}><Bar w={34} h={14} tone={2} /></span>
        <span className="kw-fade" data-on={st === 'error' || undefined}>
          <Button size="small" className="kw-retry" data-target={i === 2 ? 'retry' : undefined} data-cursor="pointer">Retry</Button>
        </span>
        <span className="kw-fade" data-on={st === 'retrying' || undefined}><Spinner size={14} className="kw-spin" /></span>
        <span className="kw-fade" data-on={st === 'ready' || undefined}><span className="kw-tag">{p.src}</span></span>
      </span>
    </div>
  )
}

function Island({ s }: { s: S }) {
  const last = useRef<{ mode: Mode; grow: boolean }>({ mode: s.mode, grow: true })
  if (last.current.mode !== s.mode) last.current = { mode: s.mode, grow: SIZE[s.mode] > SIZE[last.current.mode] }
  const grow = last.current.grow
  const g = GEO[s.mode]
  const shape: CSSProperties = {
    width: g.w,
    height: g.h,
    borderBottomLeftRadius: g.r,
    borderBottomRightRadius: g.r,
    transitionDuration: `${grow ? GROW.ms : SHRINK.ms}ms`,
    transitionTimingFunction: grow ? GROW.ease : SHRINK.ease,
    transitionDelay: grow ? '0ms' : '110ms',
  }
  const on = (m: Mode) => (s.mode === m ? true : undefined)
  return (
    <div className="kw-island">
      <span className="kw-shape" style={shape} data-target="island" />

      {/* Rest: the count, the clock, the battery */}
      <div className="kw-layer kw-rest" data-on={on('rest')} style={{ width: GEO.rest.w, height: GEO.rest.h }}>
        <span className="kw-chip" data-on={s.chip || undefined}>
          <ArrowUp size={12} strokeWidth={2.6} />
          <Roll>{String(s.count)}</Roll>
        </span>
        <span className="kw-clock">22:41</span>
        <span className="kw-batt"><span className="kw-batt__fill" /></span>
      </div>

      {/* Banner: what happened, and the one thing to do about it */}
      <div className="kw-layer kw-banner" data-on={on('banner')} style={{ width: GEO.banner.w, height: GEO.banner.h }}>
        <span className="kw-badge"><ArrowUp size={18} strokeWidth={2.4} /></span>
        <span className="kw-banner__words">
          <span className="kw-banner__title">3 updates available</span>
          <span className="kw-banner__sub">Review what changes, then update</span>
        </span>
        <Button variant="primary" size="medium" className="kw-primary" data-target="review" data-cursor="pointer">Review</Button>
      </div>

      {/* Panel: loading → content → an error on the row that caused it */}
      <div className="kw-layer kw-panel" data-on={on('panel')} style={{ width: GEO.panel.w, height: GEO.panel.h }}>
        <div className="kw-panel__head">
          <span className="kw-panel__title">Software Update</span>
          <span className="kw-panel__sub">Arch and AUR · checked just now</span>
        </div>
        <div className="kw-rows">
          {s.rows.map((st, i) => <PkgRow key={i} i={i} st={st} />)}
        </div>
        <div className="kw-panel__foot">
          <span className="kw-foot__note"><Bar w={120} h={6} tone={2} /></span>
          <Button variant="primary" size="medium" className="kw-primary" data-dim={!s.canUpdate || undefined} data-target="update" data-cursor="pointer">Update</Button>
        </div>
      </div>

      {/* Progress: the panel folds into the notch; the work goes on in it */}
      <div className="kw-layer kw-progress" data-on={on('progress')} style={{ width: GEO.progress.w, height: GEO.progress.h }}>
        <Ring p={s.pct} />
        <span className="kw-progress__words">Updating</span>
        <span className="kw-progress__step"><Roll>{`${s.step} of 3`}</Roll></span>
      </div>

      {/* Success, said once, then it gets out of the way */}
      <div className="kw-layer kw-done" data-on={on('done')} style={{ width: GEO.done.w, height: GEO.done.h }}>
        <Check on={s.mode === 'done'} size={18} className="kw-check" />
        <span className="kw-done__words">Up to date</span>
      </div>
    </div>
  )
}

const script = async (a: Act<S>) => {
  // The rows reset off stage while the island rests
  await a.wait(1300)
  a.mark('banner')
  a.put({ mode: 'banner' })
  await a.wait(1300)
  await a.move('review', { duration: 650 })
  await a.click('review')
  a.mark('loading')
  a.put({ mode: 'panel' })
  await a.wait(1300)
  // Rows resolve top to bottom; the AUR one fails on itself
  for (const i of [0, 1, 2]) {
    a.put((st) => {
      const rows = [...st.rows] as RowState[]
      rows[i] = i === 2 ? 'error' : 'ready'
      return { rows }
    })
    await a.wait(160)
  }
  a.mark('error')
  await a.wait(1500)
  await a.move('retry', { duration: 600 })
  await a.click('retry')
  a.put({ rows: ['ready', 'ready', 'retrying'] })
  await a.wait(1100)
  a.put({ rows: ['ready', 'ready', 'ready'], canUpdate: true })
  a.mark('fixed')
  await a.wait(700)
  await a.move('update', { duration: 520 })
  await a.click('update')
  a.mark('progress')
  a.put({ mode: 'progress', step: 1, pct: 0.05, chip: false })
  void a.move({ x: 760, y: 360 }, { duration: 700 })
  await a.wait(700)
  a.put({ pct: 0.4 })
  await a.wait(800)
  a.put({ step: 2, pct: 0.72 })
  await a.wait(800)
  a.put({ step: 3, pct: 1 })
  await a.wait(600)
  a.mark('done')
  a.put({ mode: 'done' })
  await a.wait(1700)
  a.put({ mode: 'rest', count: 0 })
  await a.wait(900)
  // The next check finds updates: the count buds back in (the loop's cause)
  a.snap({ rows: ['skeleton', 'skeleton', 'skeleton'], pct: 0, step: 0, canUpdate: false })
  a.put({ chip: true, count: 3 })
  await a.wait(700)
}

export default function KuwaiIsland() {
  return (
    <Stage<S>
      width={900}
      height={420}
      compact={{ below: 640, width: 358, height: 380 }}
      theme="dark"
      initial={START}
      poster={POSTER}
      script={script}
      cursor={{ at: { wide: { x: 760, y: 360 }, compact: { x: 300, y: 340 } }, style: 'arrow' }}
      className="kw"
    >
      {(_s, _rect, layout) => {
        const s = _s
        return (
          <div className="kw-desk" data-layout={layout}>
            {/* Filler desktop: a terminal and an editor, out of focus */}
            <div className="kw-win kw-win--a"><Bar w={180} h={6} tone={2} /><Bar w={240} h={6} tone={1} /><Bar w={140} h={6} tone={1} /></div>
            <div className="kw-win kw-win--b"><Bar w={120} h={6} tone={2} /><Bar w={200} h={6} tone={1} /></div>
            <Island s={s} />
          </div>
        )
      }}
    </Stage>
  )
}
