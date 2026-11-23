"""An area of interest: the rectangle on the map that one scene is built for."""
from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass, field

from .geo import metres_per_degree

MAX_AREA_KM2 = 4.0       # bigger areas make scenes too large to convert and render comfortably
MIN_SIDE_M = 60.0


def slug(text: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "_", text or "").strip("_").lower()
    return s[:40] or "area"


@dataclass
class Area:
    west: float
    south: float
    east: float
    north: float
    name: str = ""
    note: str = ""
    tags: dict = field(default_factory=dict)

    def __post_init__(self):
        self.west, self.east = sorted((float(self.west), float(self.east)))
        self.south, self.north = sorted((float(self.south), float(self.north)))
        if not self.name:
            self.name = "Area"

    # ---- geometry -------------------------------------------------------------------------------
    @property
    def center(self) -> tuple[float, float]:
        """(lat, lon) of the middle of the rectangle."""
        return (self.south + self.north) / 2.0, (self.west + self.east) / 2.0

    @property
    def size_m(self) -> tuple[float, float]:
        """(width east-west, height north-south) in metres."""
        lat, _ = self.center
        m_lon, m_lat = metres_per_degree(lat)
        return (self.east - self.west) * m_lon, (self.north - self.south) * m_lat

    @property
    def area_km2(self) -> float:
        w, h = self.size_m
        return w * h / 1e6

    @property
    def id(self) -> str:
        """A folder-safe name that is the same for the same rectangle: name plus position."""
        lat, lon = self.center
        ns = "N" if lat >= 0 else "S"
        ew = "E" if lon >= 0 else "W"
        w, h = self.size_m
        return f"{slug(self.name)}_{abs(lat):.4f}{ns}_{abs(lon):.4f}{ew}_{round(w)}x{round(h)}m"

    def problems(self, max_km2: float = MAX_AREA_KM2) -> list[str]:
        out = []
        w, h = self.size_m
        if not (-85 <= self.south < self.north <= 85):
            out.append("The area must lie between 85 degrees south and 85 degrees north.")
        if not (-180 <= self.west < self.east <= 180):
            out.append("The area must not cross the 180 degree meridian.")
        if min(w, h) < MIN_SIDE_M:
            out.append(f"The area is too small: each side must be at least {MIN_SIDE_M:.0f} m.")
        if self.area_km2 > max_km2:
            out.append(f"The area is {self.area_km2:.1f} km2; the largest is {max_km2:.0f} km2. Draw a smaller one.")
        return out

    # ---- construction and storage ---------------------------------------------------------------
    @classmethod
    def square(cls, lat: float, lon: float, side_m: float, name: str = "", **kw) -> "Area":
        m_lon, m_lat = metres_per_degree(lat)
        dlon = side_m / 2.0 / m_lon
        dlat = side_m / 2.0 / m_lat
        return cls(lon - dlon, lat - dlat, lon + dlon, lat + dlat, name=name, **kw)

    def to_feature(self) -> dict:
        props = {"name": self.name, "note": self.note, "id": self.id, **self.tags}
        ring = [[self.west, self.south], [self.east, self.south], [self.east, self.north],
                [self.west, self.north], [self.west, self.south]]
        return {"type": "Feature", "properties": props, "geometry": {"type": "Polygon", "coordinates": [ring]}}

    @classmethod
    def from_feature(cls, f: dict) -> "Area":
        ring = f["geometry"]["coordinates"][0]
        lons = [p[0] for p in ring]
        lats = [p[1] for p in ring]
        props = dict(f.get("properties") or {})
        name = props.pop("name", "")
        note = props.pop("note", "")
        props.pop("id", None)
        return cls(min(lons), min(lats), max(lons), max(lats), name=name, note=note, tags=props)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["id"] = self.id
        return d

    @classmethod
    def from_dict(cls, d: dict) -> "Area":
        return cls(d["west"], d["south"], d["east"], d["north"], name=d.get("name", ""),
                   note=d.get("note", ""), tags=d.get("tags") or {})

    def to_json(self) -> str:
        return json.dumps(self.to_dict())
