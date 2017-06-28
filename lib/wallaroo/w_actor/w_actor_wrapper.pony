use "collections"
use "sendence/guid"
use "wallaroo/boundary"
use "wallaroo/fail"
use "wallaroo/network"
use "wallaroo/recovery"
use "wallaroo/routing"
use "wallaroo/tcp_sink"
use "wallaroo/topology"

trait WActorWrapper
  be receive(msg: WMessage val)
  be process(data: Any val)
  be register_actor(id: U128, w_actor: WActorWrapper tag)
  be register_actor_for_worker(id: U128, worker: String)
  be register_as_role(role: String, w_actor: U128)
  be register_sinks(s: Array[TCPSink] val)
  be tick()
  be create_actor(builder: WActorBuilder)
  be forget_actor(id: U128)
  fun ref _register_as_role(role: String)
  fun ref _send_to(target: U128, data: Any val)
  fun ref _send_to_role(role: String, data: Any val)
  fun ref _send_to_sink[Out: Any val](sink_id: USize, output: Out)
  fun ref _roles_for(w_actor: U128): Array[String]
  fun ref _actors_in_role(role: String): Array[U128]
  fun ref _set_timer(duration: U128, callback: {()},
    is_repeating: Bool = false): WActorTimer
  fun ref _cancel_timer(t: WActorTimer)

actor WActorWithState is WActorWrapper
  let _worker_name: String
  let _id: U128
  let _event_log: EventLog
  let _guid_gen: GuidGenerator = GuidGenerator
  let _auth: AmbientAuth
  let _actor_registry: WActorRegistry
  let _central_actor_registry: CentralWActorRegistry
  var _sinks: Array[TCPSink] val = recover Array[TCPSink] end
  var _w_actor: WActor = EmptyWActor
  var _w_actor_id: U128
  var _helper: WActorHelper = EmptyWActorHelper
  let _timers: WActorTimers = WActorTimers

  // TODO: Find a way to eliminate this
  let _dummy_actor_producer: _DummyActorProducer = _DummyActorProducer

  var _seq_id: SeqId = 0

  new create(worker: String, id: U128, w_actor_builder: WActorBuilder val,
    event_log: EventLog, r: CentralWActorRegistry,
    actor_to_worker_map: Map[U128, String] val, connections: Connections,
    boundaries: Map[String, OutgoingBoundary] val, seed: U64,
    auth: AmbientAuth)
  =>
    _worker_name = worker
    _id = id
    _auth = auth
    _event_log = event_log
    _actor_registry = WActorRegistry(_worker_name, _auth, actor_to_worker_map,
      connections, boundaries, seed)
    _central_actor_registry = r
    _w_actor_id = id
    _helper = LiveWActorHelper(this)
    _w_actor = w_actor_builder(id, _helper)
    _central_actor_registry.register_actor(_w_actor_id, this)
    _event_log.register_origin(this, id)

  be receive(msg: WMessage val) =>
    """
    Called when receiving a message from another WActor
    """
    ifdef "trace" then
      @printf[I32]("receive() called at WActor %s\n".cstring(),
        _id.string().cstring())
    end
    _w_actor.receive(msg.sender, msg.payload, _helper)
    _seq_id = _seq_id + 1
    _save_state()

  be process(data: Any val) =>
    """
    Called when receiving data from a Wallaroo pipeline
    """
    ifdef "trace" then
      @printf[I32]("process() called at WActor %s\n".cstring(),
        _id.string().cstring())
    end
    _w_actor.process(data, _helper)
    _seq_id = _seq_id + 1
    _save_state()

  be register_actor(id: U128, w_actor: WActorWrapper tag) =>
    _actor_registry.register_actor(id, w_actor)

  be register_actor_for_worker(id: U128, worker: String) =>
    _actor_registry.register_actor_for_worker(id, worker)

  be register_as_role(role: String, w_actor: U128) =>
    _actor_registry.register_as_role(role, w_actor)

  be register_sinks(s: Array[TCPSink] val) =>
    _sinks = s

  be tick() =>
    """
    A tick is sent out once a second to all w_actors
    This won't scale if there are lots of w_actors
    """
    _timers.tick()

  be create_actor(builder: WActorBuilder) =>
    let new_builder = StatefulWActorWrapperBuilder(_guid_gen.u128(),
      builder)
    _central_actor_registry.create_actor(new_builder)

  be forget_actor(id: U128) =>
    _central_actor_registry.forget_actor(id)

  be replay_log_entry(uid: U128, frac_ids: None, statechange_id: U64,
    payload: ByteSeq)
  =>
    try
      _w_actor = Unpickle[WActor](payload, _auth)
    else
      Fail()
    end

  be log_flushed(low_watermark: SeqId) =>
    None

  fun ref _save_state() =>
    try
      let pickled = Pickle[WActor](_w_actor, _auth)
      let payload: Array[ByteSeq] iso =
        recover [pickled] end
      _event_log.queue_log_entry(_id, _guid_gen.u128(), None,
        U64.max_value(), _seq_id, consume payload)
      _event_log.flush_buffer(_id, _seq_id)
    else
      Fail()
    end

  fun ref _register_as_role(role: String) =>
    _central_actor_registry.register_as_role(role, _w_actor_id)

  fun ref _send_to(target: U128, data: Any val) =>
    try
      let wrapped = WMessage(_w_actor_id, target, data)
      _actor_registry.send_to(target, wrapped)
    else
      Fail()
    end

  fun ref _send_to_role(role: String, data: Any val) =>
    try
      _actor_registry.send_to_role(role, _w_actor_id, data)
    else
      Fail()
    end

  fun ref _send_to_sink[Out: Any val](sink_id: USize, output: Out) =>
    try
      // TODO: Should we create a separate TCPSink method for when we're not
      // using the pipeline metadata?  Or do we create the same metadata
      // for actor system messages.
      _sinks(sink_id).run[Out]("", 0, output, _dummy_actor_producer,
        0, None, 0, 0, 0, 0, 0)
    else
      @printf[I32]("Attempting to send to nonexistent sink id!\n".cstring())
      Fail()
    end

  fun ref _roles_for(w_actor: U128): Array[String] =>
    _actor_registry.roles_for(w_actor)

  fun ref _actors_in_role(role: String): Array[U128] =>
    _actor_registry.actors_in_role(role)

  fun ref _set_timer(duration: U128, callback: {()},
    is_repeating: Bool = false): WActorTimer
  =>
    let timer = WActorTimer(duration, callback, is_repeating)
    _timers.set_timer(timer)
    timer

  fun ref _cancel_timer(t: WActorTimer) =>
    _timers.cancel_timer(t)

interface val WActorWrapperBuilder
  fun apply(worker: String, r: CentralWActorRegistry, auth: AmbientAuth,
    event_log: EventLog, actor_to_worker_map: Map[U128, String] val,
    connections: Connections, boundaries: Map[String, OutgoingBoundary] val,
    seed: U64): WActorWrapper tag
  fun id(): U128

class val StatefulWActorWrapperBuilder
  let _id: U128
  let _w_actor_builder: WActorBuilder val

  new val create(id': U128, wab: WActorBuilder val) =>
    _id = id'
    _w_actor_builder = wab

  fun apply(worker: String, r: CentralWActorRegistry, auth: AmbientAuth,
    event_log: EventLog, actor_to_worker_map: Map[U128, String] val,
    connections: Connections, boundaries: Map[String, OutgoingBoundary] val,
    seed: U64): WActorWrapper tag
  =>
    WActorWithState(worker, _id, _w_actor_builder, event_log, r,
      actor_to_worker_map, connections, boundaries, seed, auth)

  fun id(): U128 =>
    _id

class LiveWActorHelper is WActorHelper
  let _w_actor: WActorWrapper ref

  new create(w_actor: WActorWrapper ref) =>
    _w_actor = w_actor

  fun ref send_to(target: U128, data: Any val) =>
    _w_actor._send_to(target, data)

  fun ref send_to_role(role: String, data: Any val) =>
    _w_actor._send_to_role(role, data)

  fun ref send_to_sink[Out: Any val](sink_id: USize, output: Out) =>
    _w_actor._send_to_sink[Out](sink_id, output)

  fun ref register_as_role(role: String) =>
    _w_actor._register_as_role(role)

  fun ref roles_for(w_actor: U128): Array[String] =>
    _w_actor._roles_for(w_actor)

  fun ref actors_in_role(role: String): Array[U128] =>
    _w_actor._actors_in_role(role)

  fun ref create_actor(builder: WActorBuilder) =>
    _w_actor.create_actor(builder)

  fun ref destroy_actor(id: U128) =>
    _w_actor.forget_actor(id)

  fun ref set_timer(duration: U128, callback: {()},
    is_repeating: Bool = false): WActorTimer
  =>
    _w_actor._set_timer(duration, callback, is_repeating)

  fun ref cancel_timer(t: WActorTimer) =>
    _w_actor._cancel_timer(t)

class EmptyWActorHelper is WActorHelper
  fun ref send_to(target: U128, data: Any val) =>
    None

  fun ref send_to_role(role: String, data: Any val) =>
    None

  fun ref send_to_sink[Out: Any val](sink_id: USize, output: Out) =>
    None

  fun ref register_as_role(role: String) =>
    None

  fun ref roles_for(w_actor: U128): Array[String] =>
    Array[String]

  fun ref actors_in_role(role: String): Array[U128] =>
    Array[U128]

  fun ref create_actor(builder: WActorBuilder) =>
    None

  fun ref destroy_actor(id: U128) =>
    None

  fun ref set_timer(duration: U128, callback: {()},
    is_repeating: Bool = false): WActorTimer
  =>
    WActorTimer(0, {() => None} ref)

  fun ref cancel_timer(t: WActorTimer) =>
    None

actor _DummyActorProducer is Producer
  be mute(c: Consumer) =>
    None

  be unmute(c: Consumer) =>
    None

  fun ref route_to(c: Consumer): (Route | None) =>
    None

  fun ref next_sequence_id(): SeqId =>
    0

  fun ref current_sequence_id(): SeqId =>
    0

  fun ref _x_resilience_routes(): Routes =>
    Routes

  fun ref _flush(low_watermark: SeqId) =>
    None

  fun ref update_router(router: Router val) =>
    None
