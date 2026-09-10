export interface LatLng {
  readonly latitude: number;
  readonly longitude: number;
}

/**
 * Great-circle distance in metres. Used both to judge whether a retrieved
 * network location falls inside a quest's radius, and to measure how far a
 * user has to travel — which is what makes the granted timer and the
 * eventual XP differ between two users doing the same quest.
 */
export function haversineMeters(a: LatLng, b: LatLng): number {
  const earthRadiusMeters = 6_371_000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const deltaLat = toRad(b.latitude - a.latitude);
  const deltaLon = toRad(b.longitude - a.longitude);
  const lat1 = toRad(a.latitude);
  const lat2 = toRad(b.latitude);
  const h =
    Math.sin(deltaLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(deltaLon / 2) ** 2;
  return 2 * earthRadiusMeters * Math.asin(Math.sqrt(h));
}
