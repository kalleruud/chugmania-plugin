# Camera

Source: https://openplanet.dev/docs/reference/camera

`Camera` is an Openplanet dependency for camera-space and projection helpers.

## Setup

- Add `[script] dependencies = [ "Camera" ]` to `info.toml`.

## Useful Helpers

- `Camera::ToScreenSpace(const vec3 &in pos)`: project a 3D point into 2D screen space.
- `Camera::IsBehind(const vec3 &in pos)`: check if a 3D point is behind the active camera.
- `Camera::GetCurrent()`: get the camera used for rendering.
- `Camera::GetProjectionMatrix()`: read the current projection matrix when available.

## Guidance

- Use this dependency for overlays that need world-to-screen mapping rather than rebuilding projection math manually.
- Combine `ToScreenSpace` and `IsBehind` when placing screen markers for cars, checkpoints, or world objects.
