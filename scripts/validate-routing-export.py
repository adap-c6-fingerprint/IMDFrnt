"""Check an actual export against the client's fixture and graph references.

This verifies the known fixture contract, not a client loader or route search.
"""
import argparse
import json
import math
from pathlib import Path


def require(valid, message):
    if not valid:
        raise ValueError(message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def shape(actual, sample, path):
    if isinstance(sample, dict):
        require(isinstance(actual, dict), f"{path}: object required")
        for key, value in sample.items():
            require(key in actual, f"{path}.{key}: missing")
            shape(actual[key], value, f"{path}.{key}")
    elif isinstance(sample, list):
        require(isinstance(actual, list) and len(actual) == len(sample), f"{path}: coordinate dimensions differ")
        for index, value in enumerate(sample):
            shape(actual[index], value, f"{path}[{index}]")
    elif type(sample) is bool:
        require(type(actual) is bool, f"{path}: boolean required")
    elif type(sample) is int:
        require(type(actual) is int, f"{path}: integer required")
    elif type(sample) is float:
        require(number(actual), f"{path}: finite number required")
    elif isinstance(sample, str):
        require(isinstance(actual, str) and bool(actual), f"{path}: nonempty string required")
    else:
        require(type(actual) is type(sample), f"{path}: type differs from fixture")


def position(value):
    require(isinstance(value, list) and len(value) == 2 and all(number(v) for v in value), "WGS 84 position must be [longitude, latitude]")
    require(abs(value[0]) <= 180 and abs(value[1]) <= 90, "WGS 84 coordinate range invalid")


def validate(document, fixture, levels=None):
    shape(document, {key: value for key, value in fixture.items() if key != "features"}, "root")
    require(document["type"] == "FeatureCollection", "FeatureCollection required")
    require(document["schema_version"] == fixture["schema_version"], "schema_version differs from client fixture")
    radius = document["routing_config"]["hard_search_radius_meters"]
    require(number(radius) and radius > 0, "search radius must be positive meters")
    templates = {f["properties"]["role"]: f for f in fixture["features"]}
    require(set(templates) == {"node", "edge"}, "client fixture must define node and edge")
    features = document.get("features")
    require(isinstance(features, list) and features, "features must be a nonempty array")
    ids, nodes, edges = set(), {}, []
    for feature in features:
        require(isinstance(feature, dict) and isinstance(feature.get("properties"), dict), "feature properties required")
        role = feature["properties"].get("role")
        require(role in templates, "unknown feature role")
        shape(feature, templates[role], f"feature({role})")
        require(feature["type"] == "Feature", "Feature required")
        require(feature["id"] not in ids, "duplicate feature ID")
        ids.add(feature["id"])
        geometry = feature["geometry"]
        require(geometry["type"] == templates[role]["geometry"]["type"], "geometry type differs from fixture")
        if role == "node":
            position(geometry["coordinates"])
            metadata = feature["properties"].get("metadata", {})
            require(isinstance(metadata, dict), "node metadata must be a JSON object")
            if levels is not None:
                floor = feature["properties"].get("level_id")
                require(floor in levels, "level_id not found in original IMDF")
                require(feature["properties"]["level"] == levels[floor], "level ordinal differs from original IMDF")
            nodes[feature["id"]] = feature
        else:
            edges.append(feature)
    require(nodes, "at least one node required")
    pairs = set()
    for edge in edges:
        props = edge["properties"]
        start, end = props["from"], props["to"]
        require(start in nodes and end in nodes and start != end, "invalid edge node reference")
        require(props["direction"] == templates["edge"]["properties"]["direction"], "edge direction differs from fixture")
        pair = tuple(sorted((start, end)))
        require(pair not in pairs, "duplicate undirected edge")
        pairs.add(pair)
        coords = edge["geometry"]["coordinates"]
        for value in coords:
            position(value)
        require(coords == [nodes[start]["geometry"]["coordinates"], nodes[end]["geometry"]["coordinates"]], "edge endpoints differ from referenced nodes")
    return len(nodes), len(edges)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--levels", type=Path, help="Original IMDF level.geojson for UUID/ordinal checks")
    args = parser.parse_args()
    levels = None
    try:
        if args.levels:
            data = json.loads(args.levels.read_text())
            levels = {f["id"].lower(): f["properties"]["ordinal"] for f in data["features"]}
        nodes, edges = validate(json.loads(args.export.read_text()), json.loads(args.fixture.read_text()), levels)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"FAIL: {error}\n")
    print(f"PASS: JSON/GeoJSON client fixture contract, {nodes} nodes, {edges} edges" +
          (", original IMDF level UUID/ordinal" if levels is not None else ""))


if __name__ == "__main__":
    main()
