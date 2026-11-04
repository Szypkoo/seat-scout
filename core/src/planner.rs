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

        let mut plan = self.solve_candidates(
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
        let mut plan = self.solve_candidates(&cands, board, alight, change_penalty_min)?;
        plan.full_ride_seats = cands
            .iter()
            .filter(|c| (board..alight).all(|l| c.mask[l]))
            .count() as u32;
        Some(plan)
    }

    pub fn solve_many(
        &self,
        board: usize,
        alight: usize,
        change_penalty_min: i32,
        people: usize,
    ) -> Option<Vec<Plan>> {
        let mut planner = self.clone();
        let mut plans = Vec::with_capacity(people);
        for _ in 0..people {
            let plan = planner.solve(board, alight, change_penalty_min)?;
            for run in &plan.runs {
                if let Some(info) = run.seat.and_then(|seat| planner.seats.get_mut(&seat)) {
                    for leg in run.from_stop..run.to_stop {
                        info.mask[leg] = false;
                    }
                }
            }
            plans.push(plan);
        }
        Some(plans)
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

    fn solve_candidates(
        &self,
        candidates: &[Cand],
        board: usize,
        alight: usize,
        change_penalty_min: i32,
    ) -> Option<Plan> {
        if board >= alight || alight >= self.stop_count() {
            return None;
        }
        let legs = alight - board;
        let wagons: Vec<i32> = {
            let mut wagon_numbers: Vec<i32> = candidates
                .iter()
                .map(|candidate| candidate.a.wagon)
                .collect();
            wagon_numbers.sort_unstable();
            wagon_numbers.dedup();
            wagon_numbers
        };
        let wagon_count = wagons.len();
        let no_wagon = wagon_count;
        let wagon_index = |wagon: i32| wagons.binary_search(&wagon).unwrap();
        const UNREACHABLE: i64 = i64::MIN / 4;
        let relative_stop = |i: usize| i - board;
        let mut scores = vec![vec![UNREACHABLE; wagon_count + 1]; legs + 1];
        #[derive(Clone, Copy)]
        struct PreviousStep {
            prev_stop: usize,
            prev_state: usize,
            cand: Option<usize>,
        }
        let mut previous: Vec<Vec<Option<PreviousStep>>> =
            vec![vec![None; wagon_count + 1]; legs + 1];
        scores[0][no_wagon] = 0;
        for stop in board..alight {
            let stop_index = relative_stop(stop);
            for state_index in 0..=wagon_count {
                let current_score = scores[stop_index][state_index];
                if current_score == UNREACHABLE {
                    continue;
                }
                if current_score > scores[stop_index + 1][state_index] {
                    scores[stop_index + 1][state_index] = current_score;
                    previous[stop_index + 1][state_index] = Some(PreviousStep {
                        prev_stop: stop,
                        prev_state: state_index,
                        cand: None,
                    });
                }
                for (candidate_index, candidate) in candidates.iter().enumerate() {
                    if !candidate.mask[stop] {
                        continue;
                    }
                    let next_state = wagon_index(candidate.a.wagon);
                    let change = if state_index == no_wagon {
                        0
                    } else {
                        change_penalty_min as i64 * 1000
                            + (i64::from(wagons[state_index]) - i64::from(candidate.a.wagon)).abs()
                    };
                    let mut end_stop = stop;
                    while end_stop < alight && candidate.mask[end_stop] {
                        end_stop += 1;
                        let end_index = relative_stop(end_stop);
                        let score = current_score
                            + self.span_minutes(stop, end_stop) as i64 * 1000
                            + candidate.window_bonus
                            - change;
                        if score > scores[end_index][next_state] {
                            scores[end_index][next_state] = score;
                            previous[end_index][next_state] = Some(PreviousStep {
                                prev_stop: stop,
                                prev_state: state_index,
                                cand: Some(candidate_index),
                            });
                        }
                    }
                }
            }
        }
        let (mut best_state, mut best) = (no_wagon, UNREACHABLE);
        for (state_index, v) in scores[legs].iter().enumerate() {
            if *v > best {
                best = *v;
                best_state = state_index;
            }
        }
        if best == UNREACHABLE {
            return None;
        }
        let mut raw: Vec<(PreviousStep, usize)> = Vec::new();
        let (mut stop, mut state) = (alight, best_state);
        while stop > board {
            let step = previous[relative_stop(stop)][state]?;
            raw.push((step, stop));
            stop = step.prev_stop;
            state = step.prev_state;
        }
        raw.reverse();
        let mut runs: Vec<PlanRun> = Vec::new();
        for (step, end) in raw {
            let minutes = self.span_minutes(step.prev_stop, end);
            let (seat, seat2, window) = match step.cand {
                Some(candidate_index) => (
                    Some(candidates[candidate_index].a),
                    candidates[candidate_index].b,
                    candidates[candidate_index].window,
                ),
                None => (None, None, false),
            };
            match runs.last_mut() {
                Some(last)
                    if last.seat == seat
                        && last.seat2 == seat2
                        && last.to_stop == step.prev_stop =>
                {
                    last.to_stop = end;
                    last.minutes += minutes;
                }
                _ => runs.push(PlanRun {
                    from_stop: step.prev_stop,
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
