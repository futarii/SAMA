#pragma once

#include "common.h"
static bool file_exists(const string& path) {
    ifstream in(path);
    return in.good();
}

static vector<double> parse_numbers(const string& line) {
    vector<double> out;
    stringstream ss(line);
    double v;
    while (ss >> v) {
        out.push_back(v);
    }
    return out;
}

static void update_bounds(Bounds& b, const Point& p) {
    b.xmin = min(b.xmin, p.x);
    b.xmax = max(b.xmax, p.x);
    b.ymin = min(b.ymin, p.y);
    b.ymax = max(b.ymax, p.y);
}

static Dataset load_dataset(const string& path) {
    ifstream in(path);
    if (!in) {
        throw runtime_error("cannot open dataset: " + path);
    }

    string first_line;
    if (!getline(in, first_line)) {
        throw runtime_error("empty dataset: " + path);
    }
    vector<double> first = parse_numbers(first_line);
    if (first.size() < 2) {
        throw runtime_error("first line does not contain two numbers: " + path);
    }

    Dataset ds;
    bool looks_like_header = first[0] > 0 && fabs(first[0] - floor(first[0])) < 1e-9 &&
                             fabs(first[1] - 2.0) < 1e-9;
    if (looks_like_header) {
        ds.had_header = true;
        int n = static_cast<int>(first[0]);
        ds.points.reserve(n);
        for (int i = 0; i < n; i++) {
            Point p;
            if (!(in >> p.x >> p.y)) {
                throw runtime_error("header count exceeds available points: " + path);
            }
            ds.points.push_back(p);
            update_bounds(ds.box, p);
        }
    } else {
        Point p{first[0], first[1]};
        ds.points.push_back(p);
        update_bounds(ds.box, p);
        while (in >> p.x >> p.y) {
            ds.points.push_back(p);
            update_bounds(ds.box, p);
        }
    }

    if (ds.points.empty()) {
        throw runtime_error("no points in dataset: " + path);
    }
    return ds;
}

static void write_header_dataset(const Dataset& ds, const string& path) {
    ofstream out(path);
    if (!out) {
        throw runtime_error("cannot write: " + path);
    }
    out << ds.points.size() << "\n2\n";
    out << setprecision(12);
    for (const Point& p : ds.points) {
        out << p.x << " " << p.y << "\n";
    }
}

static void translate_to_origin(Dataset& ds) {
    const double ox = ds.box.xmin;
    const double oy = ds.box.ymin;
    Bounds shifted;
    for (Point& p : ds.points) {
        p.x -= ox;
        p.y -= oy;
        update_bounds(shifted, p);
    }
    ds.box = shifted;
}

static Bounds translated_box(const Bounds& box, double ox, double oy) {
    Bounds out;
    out.xmin = box.xmin - ox;
    out.xmax = box.xmax - ox;
    out.ymin = box.ymin - oy;
    out.ymax = box.ymax - oy;
    return out;
}

static double scott_bandwidth(const vector<Point>& pts, double factor) {
    const int n = static_cast<int>(pts.size());
    double sx = 0.0;
    double sy = 0.0;
    for (const Point& p : pts) {
        sx += p.x;
        sy += p.y;
    }
    double mx = sx / n;
    double my = sy / n;
    double vx = 0.0;
    double vy = 0.0;
    for (const Point& p : pts) {
        vx += (p.x - mx) * (p.x - mx) / max(1, n - 1);
        vy += (p.y - my) * (p.y - my) / max(1, n - 1);
    }
    double hx = factor * pow(static_cast<double>(n), -1.0 / 6.0) * sqrt(vx);
    double hy = factor * pow(static_cast<double>(n), -1.0 / 6.0) * sqrt(vy);
    return sqrt(hx * hx + hy * hy);
}

