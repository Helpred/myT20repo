# Physics v7 — sprung hull / stable running gear

This pass fixes the excessive whole-tank rocking from v6.

Changes:
- the visual hierarchy is split into `RunningGear` and `SprungBody`;
- tracks and road wheels follow the terrain support plane, but no longer receive acceleration/braking rock;
- only the hull + turret get the small damped longitudinal pitch;
- rocking amplitude is reduced from roughly 6 degrees possible in v6 to about 1.5 degrees maximum;
- terrain pitch/roll is clamped and softened so a rigid track mesh does not pivot like a ball over a sharp ledge;
- camera is now attached to a stable `CameraYawPivot` under the tank root: it follows turret yaw but ignores suspension/body pitch/roll;
- Viking suspension visual travel is reduced and its road wheels are biased upward slightly so they stay inside the track envelope;
- Wasp/Mamont wheel travel was also slightly tightened to avoid belt penetration on hard edges.

The track belt itself remains a rigid imported mesh. True belt sag/deformation between individual road wheels will require either a generated segmented belt or a vertex-deformation shader and is a separate fidelity milestone.
