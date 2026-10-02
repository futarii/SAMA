#pragma once
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <queue>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace std;

struct Point {
    double x = 0.0;
    double y = 0.0;
};

struct Bounds {
    double xmin = numeric_limits<double>::infinity();
    double xmax = -numeric_limits<double>::infinity();
    double ymin = numeric_limits<double>::infinity();
    double ymax = -numeric_limits<double>::infinity();
};

struct Moment2 {
    long long count = 0;
    double sum_x = 0.0;
    double sum_y = 0.0;
    double sum_norm2 = 0.0;
    double sum_x2 = 0.0;
    double sum_xy = 0.0;
    double sum_y2 = 0.0;
    double sum_x_norm2 = 0.0;
    double sum_y_norm2 = 0.0;
    double sum_norm4 = 0.0;

    void add(const Moment2& other) {
        count += other.count;
        sum_x += other.sum_x;
        sum_y += other.sum_y;
        sum_norm2 += other.sum_norm2;
        sum_x2 += other.sum_x2;
        sum_xy += other.sum_xy;
        sum_y2 += other.sum_y2;
        sum_x_norm2 += other.sum_x_norm2;
        sum_y_norm2 += other.sum_y_norm2;
        sum_norm4 += other.sum_norm4;
    }
};

struct Node {
    Bounds box;
    Moment2 moment;
    int left = -1;
    int right = -1;
    int begin = 0;
    int end = 0;
    int leaf_count = 1;

    bool is_leaf() const {
        return left < 0 && right < 0;
    }
};

struct Tile {
    int r0 = 0;
    int r1 = 0;
    int c0 = 0;
    int c1 = 0;
};

struct Dataset {
    vector<Point> points;
    Bounds box;
    bool had_header = false;
};

struct GridInfo {
    int rows = 0;
    int cols = 0;
    Bounds box;
    double incr_x = 0.0;
    double incr_y = 0.0;

    Point at(int r, int c) const {
        return {box.xmin + r * incr_x, box.ymin + c * incr_y};
    }

    Bounds tile_bounds(const Tile& t) const {
        Point a = at(t.r0, t.c0);
        Point b = at(t.r1, t.c1);
        Bounds out;
        out.xmin = min(a.x, b.x);
        out.xmax = max(a.x, b.x);
        out.ymin = min(a.y, b.y);
        out.ymax = max(a.y, b.y);
        return out;
    }
};

struct Counters {
    long long empty_nodes = 0;
    long long full_nodes = 0;
    long long boundary_nodes = 0;
    long long boundary_points = 0;
    long long root_full_leaf_nodes = 0;
    long long root_empty_leaf_nodes = 0;
    long long root_boundary_leaf_nodes = 0;
    long long root_full_points = 0;
    long long root_empty_points = 0;
    long long root_boundary_points = 0;
    long long direct_point_pixel_tests = 0;
    long long full_work_aggregated = 0;
    long long boundary_work_scanned = 0;
    long long empty_work_pruned = 0;
    long long total_potential_work = 0;
    long long evaluated_tiles = 0;
    long long split_tiles = 0;
};

struct SbdParams {
    int rows = 256;
    int cols = 256;
    double bandwidth_factor = 1.0;
    int kernel_type = 1;
    int leaf_capacity = 64;
    int min_tile_side = 8;
    long long split_work_limit = 200000;
    int variant = 0;
    bool collect_work_stats = false;
    bool has_query_box = false;
    Bounds query_box;
};

struct SbdResult {
    vector<double> values;
    double seconds = 0.0;
    double bandwidth = 0.0;
    Counters counters;
};

