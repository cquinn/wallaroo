/*

Copyright 2017 The Wallaroo Authors.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 implied. See the License for the specific language governing
 permissions and limitations under the License.

*/

use "buffered"
use "collections"
use "time"
use "wallaroo"
use "wallaroo/core/common"
use "wallaroo_labs/mort"
use "wallaroo/core/routing"
use "wallaroo/core/state"


interface val Computation[In: Any val, Out: Any val]
  fun name(): String
  fun val runner_builder(step_group_id: RoutingId, parallelization: USize):
    RunnerBuilder

interface val StatelessComputation[In: Any val, Out: Any val] is
  Computation[In, Out]
  fun apply(input: In): (Out | Array[Out] val | None)

  fun val runner_builder(step_group_id: RoutingId, parallelization: USize):
    RunnerBuilder
  =>
    StatelessComputationRunnerBuilder[In, Out](this, step_group_id,
      parallelization)

interface val StateComputation[In: Any val, Out: Any val, S: State ref] is
  (Computation[In, Out] & StateInitializer[In, Out, S])
  // Return a tuple containing the result of the computation (which is None
  // if there is no value to forward) and a StateChange if there was one (or
  // None to indicate no state change).
  fun apply(input: In, state: S): (Out | Array[Out] val | None)

  fun initial_state(): S

  fun encoder_decoder(): StateEncoderDecoder[S] =>
    PonySerializeStateEncoderDecoder[S]

  ////////////////////////////
  // Not implemented by user
  ////////////////////////////
  fun val runner_builder(step_group_id: RoutingId, parallelization: USize):
    RunnerBuilder
  =>
    StateRunnerBuilder[In, Out, S](this, step_group_id, parallelization)

  fun val state_wrapper(key: Key): StateWrapper[In, Out, S] =>
    StateComputationWrapper[In, Out, S](this, initial_state())

  fun val decode(in_reader: Reader, auth: AmbientAuth):
    StateWrapper[In, Out, S] ?
  =>
    let state = encoder_decoder().decode(in_reader, auth)?
    StateComputationWrapper[In, Out, S](this, state)

class StateComputationWrapper[In: Any val, Out: Any val, S: State ref] is
  StateWrapper[In, Out, S]
  let _comp: StateComputation[In, Out, S]
  let _encoder_decoder: StateEncoderDecoder[S]
  let _state: S
  let _dummy_outs: Array[Out] val = recover val Array[Out] end

  new create(sc: StateComputation[In, Out, S], state: S)
  =>
    _comp = sc
    _encoder_decoder = sc.encoder_decoder()
    _state = state

  fun ref apply(input: In, event_ts: U64, wall_time: U64):
    (Out | Array[Out] val | None)
  =>
    _comp(input, _state)

  fun ref on_timeout(wall_time: U64): Array[Out] val =>
    // We don't trigger on timeouts, so we return an empty array to indicate
    // there are no triggered outputs.
    _dummy_outs

  fun ref encode(auth: AmbientAuth): ByteSeq =>
     _encoder_decoder.encode(_state, auth)
