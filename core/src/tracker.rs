use crate::dates::to_minutes;
use crate::model::Stop;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TripState {
    NotStarted,
    AtStation(usize),
    Between(usize, usize),
    Finished,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    Schedule,
    Actual,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct StopPrediction {
    pub sched_arr: i64,
    pub sched_dep: i64,
    pub arr: i64,
    pub dep: i64,
    pub arr_actual: bool,
    pub dep_actual: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TripStatus {
    pub state: TripState,
    pub source: Source,
    pub delay_min: Option<i64>,
    pub next_stop: Option<usize>,
    pub minutes_to_next: Option<i64>,
    pub progress: f64,
    pub stops: Vec<StopPrediction>,
}

pub fn track(stops: &[Stop], now: i64) -> Option<TripStatus> {
    let stop_count = stops.len();
    if stop_count < 2 {
        return None;
    }
    let mut schedule = Vec::with_capacity(stop_count);
    for stop in stops {
        let arrival = to_minutes(&stop.arr);
        let departure = to_minutes(&stop.dep);
        let (arrival, departure) = match (arrival, departure) {
            (Some(arrival), Some(departure)) => (arrival, departure.max(arrival)),
            (Some(arrival), None) => (arrival, arrival),
            (None, Some(departure)) => (departure, departure),
            (None, None) => return None,
        };
        schedule.push((arrival, departure));
    }
    let actual_times: Vec<(Option<i64>, Option<i64>)> = stops
        .iter()
        .map(|stop| (to_minutes(&stop.arr_actual), to_minutes(&stop.dep_actual)))
        .collect();

    let mut event: Option<(usize, bool, i64)> = None;
    for index in (0..stop_count).rev() {
        if let Some(departure) = actual_times[index].1.filter(|&time| time <= now) {
            event = Some((index, true, departure - schedule[index].1));
            break;
        }
        if let Some(arrival) = actual_times[index].0.filter(|&time| time <= now) {
            event = Some((index, false, arrival - schedule[index].0));
            break;
        }
    }
    let delay = event.map(|last_event| last_event.2);
    let source = if event.is_some() {
        Source::Actual
    } else {
        Source::Schedule
    };

    let state = match event {
        Some((index, true, _)) if index + 1 >= stop_count => TripState::Finished,
        Some((index, true, _)) => TripState::Between(index, index + 1),
        Some((index, false, _)) if index + 1 >= stop_count => TripState::Finished,
        Some((index, false, _)) => TripState::AtStation(index),
        None => {
            if now < schedule[0].1 {
                TripState::NotStarted
            } else if now >= schedule[stop_count - 1].0 {
                TripState::Finished
            } else {
                let mut current_state = TripState::NotStarted;
                for index in 0..stop_count {
                    if now >= schedule[index].0 && now <= schedule[index].1 {
                        current_state = TripState::AtStation(index);
                        break;
                    }
                    if index + 1 < stop_count
                        && now > schedule[index].1
                        && now < schedule[index + 1].0
                    {
                        current_state = TripState::Between(index, index + 1);
                        break;
                    }
                }
                current_state
            }
        }
    };

    let last_event_index = event.map(|last_event| last_event.0);
    let delay_minutes = delay.unwrap_or(0);
    let predictions: Vec<StopPrediction> = (0..stop_count)
        .map(|index| {
            let (scheduled_arrival, scheduled_departure) = schedule[index];
            let after_last_event =
                last_event_index.is_none_or(|last_event| index > last_event) && event.is_some();
            let shift = if after_last_event { delay_minutes } else { 0 };
            let mut arr = actual_times[index].0.unwrap_or(scheduled_arrival + shift);
            let arrived_here = matches!(event, Some((last_event, false, _)) if last_event == index);
            let mut dep = actual_times[index].1.unwrap_or(if arrived_here {
                scheduled_departure.max(arr)
            } else {
                scheduled_departure + shift
            });
            if dep < arr {
                dep = arr;
            }
            if let TripState::Between(_, to) = state {
                if index == to && actual_times[index].0.is_none() && arr < now {
                    let adjustment = now - arr;
                    arr += adjustment;
                    dep = dep.max(arr);
                }
            }
            StopPrediction {
                sched_arr: scheduled_arrival,
                sched_dep: scheduled_departure,
                arr,
                dep,
                arr_actual: actual_times[index].0.is_some_and(|time| time <= now),
                dep_actual: actual_times[index].1.is_some_and(|time| time <= now),
            }
        })
        .collect();

    let next_stop = match state {
        TripState::NotStarted => Some(0),
        TripState::AtStation(index) => Some(index),
        TripState::Between(_, next_index) => Some(next_index),
        TripState::Finished => None,
    };
    let minutes_to_next = next_stop.map(|index| match state {
        TripState::NotStarted => predictions[index].dep - now,
        _ => predictions[index].arr - now,
    });

    let start = predictions[0].dep;
    let end = predictions[stop_count - 1].arr;
    let progress = match state {
        TripState::NotStarted => 0.0,
        TripState::Finished => 1.0,
        _ if end > start => ((now - start) as f64 / (end - start) as f64).clamp(0.0, 0.99),
        _ => 0.0,
    };

    Some(TripStatus {
        state,
        source,
        delay_min: delay,
        next_stop,
        minutes_to_next,
        progress,
        stops: predictions,
    })
}
