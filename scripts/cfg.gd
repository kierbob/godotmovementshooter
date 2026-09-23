class_name Cfg
## All movement tuning, copied 1:1 from the web game's src/config.js. Units: meters, seconds.

const TICK_RATE := 120
const TICK_DT := 1.0 / 120.0

# Player hitbox
const PLAYER_HALF_WIDTH := 0.35
const PLAYER_HEIGHT := 1.8
const PLAYER_EYE_HEIGHT := 1.6
const PLAYER_CROUCH_HEIGHT := 1.0
const PLAYER_CROUCH_EYE_HEIGHT := 0.8
const PLAYER_CROUCH_SPEED := 4.5
const PLAYER_CROUCH_BRAKE := 60.0 # m/s lost per second when crouching above crouch speed (no crouch-"sliding")
const PLAYER_STEP_HEIGHT := 0.45 # ledges this low are walked up automatically

# Apex-style air control: hold a direction and your momentum swings toward it.
const AIR_TURN_RATE := 3.5 # radians/sec momentum can turn toward your aim (~200°/s)
const AIR_ACCEL := 3.0 # gain up to walk speed if you jumped slow (no gain above it)
const AIR_BRAKE_ANGLE := 2.4 # steering more than ~137° away from travel = brake instead of turn
const AIR_BRAKE := 8.0 # m/s lost per second while braking in the air

const JUMP_PAD_LAUNCH := 17.0 # upward speed (~6.5 m high)
const JUMP_PAD_FORWARD_BOOST := 2.0 # extra speed in the direction you were already moving
const JUMP_PAD_COOLDOWN := 0.5

# Wall jump: touch a wall in the air and press jump to kick off it.
const WALL_REACH := 0.12 # how close counts as touching a wall
const WALL_COYOTE_TIME := 0.15 # can still wall jump this long after leaving the wall
const WALL_JUMP_UP := 8.0 # upward speed from a wall jump
const WALL_JUMP_PUSH := 7.5 # speed pushed away from the wall
const WALL_KEEP_ALONG := 1.0 # fraction of along-the-wall momentum kept
const WALL_SPEED_BUMP := 1.5 # extra speed added on every wall jump
const WALL_MAX_JUMPS := 4 # wall jumps before you have to touch the ground
const WALL_SAME_WALL_DELAY := 0.35 # min time between two jumps off the same wall face

const SLIDE_MIN_SPEED := 6.0 # need at least this much speed to start a slide
const SLIDE_BOOST := 4.0 # speed added when a slide starts (if off cooldown)
const SLIDE_BOOST_MAX_SPEED := 18.0 # boost won't push you past this
const SLIDE_BOOST_COOLDOWN := 1.2 # seconds between boosted slides
const SLIDE_FRICTION := 5.0 # m/s lost per second while sliding
const SLIDE_END_SPEED := 5.0 # slide ends below this
const SLIDE_STEER_RATE := 1.6 # radians/sec you can curve a slide with the mouse
const SLIDE_LAND_MIN_AIR_TIME := 0.3 # airtime needed for a boosted landing slide

const MOVE_WALK_SPEED := 9.0
const MOVE_SPRINT_SPEED := 12.5
const MOVE_GROUND_ACCEL := 70.0
const MOVE_FRICTION := 9.0
const MOVE_STOP_SPEED := 3.0 # friction acts as if at least this fast, so you stop crisply
const MOVE_GROUND_TURN_RATE := 7.0 # radians/sec you carve toward your aim while above run speed on the ground
const MOVE_OVERSPEED_DECAY := 2.5 # extra speed fades this fast while you keep pushing that way
const MOVE_LAND_GRACE := 0.1 # no friction this long after landing, so jump chains keep speed
const MOVE_MAX_SPEED := 25.0 # hard momentum cap
const MOVE_MAX_FALL_SPEED := 45.0
const MOVE_MAX_RISE_SPEED := 24.0
const MOVE_KNOCKBACK_GRACE := 0.15 # after a knockback, friction/air braking pause for a moment
const MOVE_KNOCKBACK_GRACE_PER := 0.015 # ...plus this much per m/s of knockback
const MOVE_GRAVITY := 22.0
const MOVE_JUMP_VELOCITY := 7.0 # ~1.1 m jump height
const MOVE_COYOTE_TIME := 0.1
const MOVE_JUMP_BUFFER := 0.12
