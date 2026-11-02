use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct SeatRef {
    pub wagon: i32,
    pub number: u16,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PlanRun {
    pub from_stop: usize,
    pub to_stop: usize,
    pub seat: Option<SeatRef>,
    pub seat2: Option<SeatRef>,
    pub window: bool,
    pub minutes: i32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Plan {
    pub runs: Vec<PlanRun>,
    pub seated_minutes: i32,
    pub total_minutes: i32,
    pub changes: u32,
    pub full_ride_seats: u32,
}

impl Plan {
    pub fn seated_percent(&self) -> i32 {
        if self.total_minutes == 0 {
            0
        } else {
            (self.seated_minutes as f64 / self.total_minutes as f64 * 100.0).round() as i32
        }
    }
}

pub const ADJACENT_DIST: i32 = 45;

#[derive(Clone)]
struct SeatInfo {
    window: bool,
    xy: Option<(i32, i32)>,
    mask: Vec<bool>,
}

struct Cand {
    a: SeatRef,
    b: Option<SeatRef>,
    window_bonus: i64,
    window: bool,
    mask: Vec<bool>,
}

#[derive(Clone)]
pub struct Planner {
    arr: Vec<i32>,
    dep: Vec<i32>,
    seats: BTreeMap<SeatRef, SeatInfo>,
}

impl Planner {
    pub fn new(arr: Vec<i32>, dep: Vec<i32>) -> Self {
        assert_eq!(arr.len(), dep.len());
        Planner {
            arr,
            dep,
            seats: BTreeMap::new(),
        }
    }

    pub fn stop_count(&self) -> usize {
        self.arr.len()
    }

    pub fn leg_count(&self) -> usize {
        self.arr.len().saturating_sub(1)
    }

    pub fn span_minutes(&self, from: usize, to: usize) -> i32 {
        self.arr[to].saturating_sub(self.dep[from]).max(0)
    }

    pub fn add_free_seat(&mut self, leg: usize, seat: SeatRef, window: bool) {
        self.add_free_seat_xy(leg, seat, window, None);
    }

    pub fn add_free_seat_xy(
        &mut self,
        leg: usize,
        seat: SeatRef,
        window: bool,
        xy: Option<(i32, i32)>,
    ) {
        if leg >= self.leg_count() {
            return;
        }
        let n = self.leg_count();
        let e = self.seats.entry(seat).or_insert_with(|| SeatInfo {
            window,
            xy,
            mask: vec![false; n],
        });
        e.window |= window;
        if e.xy.is_none() {
            e.xy = xy;
        }
        e.mask[leg] = true;
    }

    fn singles(&self, board: usize, alight: usize) -> Vec<Cand> {
        self.seats
            .iter()
            .filter(|(_, i)| (board..alight).any(|l| i.mask[l]))
            .map(|(s, i)| Cand {
                a: *s,
                b: None,
                window_bonus: i.window as i64,
                window: i.window,
                mask: i.mask.clone(),
            })
            .collect()
    }

    fn pairs(&self, board: usize, alight: usize) -> Vec<Cand> {
        let list: Vec<(&SeatRef, &SeatInfo)> = self
            .seats
            .iter()
            .filter(|(_, i)| i.xy.is_some() && (board..alight).any(|l| i.mask[l]))
            .collect();
        let mut out = Vec::new();
        for (i, (sa, ia)) in list.iter().enumerate() {
            let (ax, ay) = ia.xy.unwrap();
            for (sb, ib) in list.iter().skip(i + 1) {
                if sb.wagon != sa.wagon {
                    break;
                }
                let (bx, by) = ib.xy.unwrap();
                let (dx, dy) = (
                    i128::from(ax) - i128::from(bx),
                    i128::from(ay) - i128::from(by),
                );
                if dx * dx + dy * dy > i128::from(ADJACENT_DIST).pow(2) {
                    continue;
                }
                let mask: Vec<bool> = ia
                    .mask
                    .iter()
                    .zip(&ib.mask)
                    .map(|(x, y)| *x && *y)
                    .collect();
                if !(board..alight).any(|l| mask[l]) {
                    continue;
                }
                out.push(Cand {
                    a: **sa,
                    b: Some(**sb),
                    window_bonus: ia.window as i64 + ib.window as i64,
                    window: ia.window || ib.window,
                    mask,
                });
            }
        }
        out
    }

    pub fn full_ride_seats(&self, board: usize, alight: usize) -> u32 {
        if board >= alight || alight >= self.stop_count() {
            return 0;
        }

        self.seats
            .values()
            .filter(|i| (board..alight).all(|l| i.mask[l]))
            .count() as u32
    }

    pub fn full_ride_pairs(&self, board: usize, alight: usize) -> u32 {
        if board >= alight || alight >= self.stop_count() {
            return 0;
        }

        self.pairs(board, alight)
            .iter()
            .filter(|c| (board..alight).all(|l| c.mask[l]))
            .count() as u32
    }

    pub fn solve(&self, board: usize, alight: usize, change_penalty_min: i32) -> Option<Plan> {
        if board >= alight || alight >= self.stop_count() {
            return None;
        }

        let mut plan = self.solve_cands(
            &self.singles(board, alight),
            board,
            alight,
            change_penalty_min,
        )?;
        plan.full_ride_seats = self.full_ride_seats(board, alight);
        Some(plan)
    }

    pub fn solve_pairs(
        &self,
        board: usize,
        alight: usize,
        change_penalty_min: i32,
    ) -> Option<Plan> {
        if board >= alight || alight >= self.stop_count() {
            return None;
        }

        let cands = self.pairs(board, alight);
        let mut plan = self.solve_cands(&cands, board, alight, change_penalty_min)?;
        plan.full_ride_seats = cands
            .iter()
            .filter(|c| (board..alight).all(|l| c.mask[l]))
            .count() as u32;
        Some(plan)
    }

    pub fn solve_separate(
        &self,
        board: usize,
        alight: usize,
        change_penalty_min: i32,
    ) -> Option<(Plan, Plan)> {
        let first = self.solve(board, alight, change_penalty_min)?;
        let mut rest = self.clone();
        for r in first.runs.iter().filter(|r| r.seat.is_some()) {
            if let Some(info) = r.seat.and_then(|s| rest.seats.get_mut(&s)) {
                for l in r.from_stop..r.to_stop {
                    info.mask[l] = false;
                }
            }
        }
        let second = rest.solve(board, alight, change_penalty_min)?;
        Some((first, second))
    }

    fn solve_cands(
        &self,
        cands: &[Cand],
        board: usize,
        alight: usize,
        change_penalty_min: i32,
    ) -> Option<Plan> {
        if board >= alight || alight >= self.stop_count() {
            return None;
        }
        let legs = alight - board;
        let wagons: Vec<i32> = {
            let mut w: Vec<i32> = cands.iter().map(|c| c.a.wagon).collect();
            w.sort_unstable();
            w.dedup();
            w
        };
        let nw = wagons.len();
        let none = nw;
        let widx = |wagon: i32| wagons.binary_search(&wagon).unwrap();
        const NEG: i64 = i64::MIN / 4;
        let k = |i: usize| i - board;
        let mut dp = vec![vec![NEG; nw + 1]; legs + 1];
        #[derive(Clone, Copy)]
        struct Back {
            prev_stop: usize,
            prev_state: usize,
            cand: Option<usize>,
        }
        let mut back: Vec<Vec<Option<Back>>> = vec![vec![None; nw + 1]; legs + 1];
        dp[0][none] = 0;
        for s in board..alight {
            let ks = k(s);
            for st in 0..=nw {
                let cur = dp[ks][st];
                if cur == NEG {
                    continue;
                }
                if cur > dp[ks + 1][st] {
                    dp[ks + 1][st] = cur;
                    back[ks + 1][st] = Some(Back {
                        prev_stop: s,
                        prev_state: st,
                        cand: None,
                    });
                }
                for (ci, c) in cands.iter().enumerate() {
                    if !c.mask[s] {
                        continue;
                    }
                    let ns = widx(c.a.wagon);
                    let change = if st == none {
                        0
                    } else {
                        change_penalty_min as i64 * 1000
                            + (i64::from(wagons[st]) - i64::from(c.a.wagon)).abs()
                    };
                    let mut m = s;
                    while m < alight && c.mask[m] {
                        m += 1;
                        let km = k(m);
                        let val =
                            cur + self.span_minutes(s, m) as i64 * 1000 + c.window_bonus - change;
                        if val > dp[km][ns] {
                            dp[km][ns] = val;
                            back[km][ns] = Some(Back {
                                prev_stop: s,
                                prev_state: st,
                                cand: Some(ci),
                            });
                        }
                    }
                }
            }
        }
        let (mut best_state, mut best) = (none, NEG);
        for (st, v) in dp[legs].iter().enumerate() {
            if *v > best {
                best = *v;
                best_state = st;
            }
        }
        if best == NEG {
            return None;
        }
        let mut raw: Vec<(Back, usize)> = Vec::new();
        let (mut stop, mut state) = (alight, best_state);
        while stop > board {
            let b = back[k(stop)][state]?;
            raw.push((b, stop));
            stop = b.prev_stop;
            state = b.prev_state;
        }
        raw.reverse();
        let mut runs: Vec<PlanRun> = Vec::new();
        for (b, end) in raw {
            let minutes = self.span_minutes(b.prev_stop, end);
            let (seat, seat2, window) = match b.cand {
                Some(ci) => (Some(cands[ci].a), cands[ci].b, cands[ci].window),
                None => (None, None, false),
            };
            match runs.last_mut() {
                Some(last)
                    if last.seat == seat && last.seat2 == seat2 && last.to_stop == b.prev_stop =>
                {
                    last.to_stop = end;
                    last.minutes += minutes;
                }
                _ => runs.push(PlanRun {
                    from_stop: b.prev_stop,
                    to_stop: end,
                    seat,
                    seat2,
                    window,
                    minutes,
                }),
            }
        }
        let seated: i32 = runs
            .iter()
            .filter(|r| r.seat.is_some())
            .map(|r| r.minutes)
            .sum();
        let seats_used = runs.iter().filter(|r| r.seat.is_some()).count() as u32;
        Some(Plan {
            seated_minutes: seated,
            total_minutes: self.span_minutes(board, alight),
            changes: seats_used.saturating_sub(1),
            full_ride_seats: 0,
            runs,
        })
    }
}
