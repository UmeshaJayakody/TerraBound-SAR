"""Open data the scenes are built from: elevation, land cover and OpenStreetMap features.

Every source is downloaded once per area and kept in the cache (see config.cache_dir), so building
the same area again, or running more views of it, needs no internet connection.
"""
