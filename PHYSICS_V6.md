# Physics v6

This pass focuses on tracked-tank feel without changing the current camera, weapons or arena fallback.

Changes:
- longitudinal coasting inertia after W/S release;
- stronger service braking only when reversing direction;
- damped chassis pitch/rock on acceleration and stopping;
- softer A/D differential steering with angular acceleration smoothing;
- fast differential-track damping after steering release to reduce yaw scrub/sliding while keeping forward roll;
- low-obstacle step-up probes per hull (Wasp/Viking/Mamont have different limits);
- right-track UV direction corrected;
- left/right track speeds included in network state and server snapshots;
- suspension/wheel animation remains tied to the individual track speeds.

The project still uses CharacterBody3D for the collision body. A later milestone can replace the support/step logic with a full ray-based tracked chassis closer to LegacyTrackedChassis.
