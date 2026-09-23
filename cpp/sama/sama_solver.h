#pragma once

#include "geometry.h"
#include "kd_tree.h"
#include "kernel.h"
class SbdSolver2 {
public:
    SbdSolver2(const Tree2& tree, GridInfo grid, double bandwidth, const SbdParams& params)
        : tree_(tree), grid_(grid), h_(bandwidth), params_(params) {
        values_.assign(static_cast<size_t>(grid_.rows) * grid_.cols, 0.0);
    }

    SbdResult run() {
        auto start = chrono::high_resolution_clock::now();
        solve_tile(Tile{0, grid_.rows - 1, 0, grid_.cols - 1}, Moment2{}, vector<int>{0});
        auto end = chrono::high_resolution_clock::now();
        SbdResult result;
        result.values = std::move(values_);
        result.seconds = chrono::duration_cast<chrono::duration<double>>(end - start).count();
        result.bandwidth = h_;
        result.counters = counters_;
        return result;
    }

private:
    const Tree2& tree_;
    GridInfo grid_;
    double h_ = 0.0;
    SbdParams params_;
    vector<double> values_;
    Counters counters_;
    bool root_stats_recorded_ = false;

    int tile_rows(const Tile& t) const { return t.r1 - t.r0 + 1; }
    int tile_cols(const Tile& t) const { return t.c1 - t.c0 + 1; }
    long long tile_pixels(const Tile& t) const {
        return static_cast<long long>(tile_rows(t)) * tile_cols(t);
    }

    vector<Tile> split_tile(const Tile& t) const {
        int rm = (t.r0 + t.r1) / 2;
        int cm = (t.c0 + t.c1) / 2;
        vector<Tile> out;
        out.push_back({t.r0, rm, t.c0, cm});
        if (cm + 1 <= t.c1) out.push_back({t.r0, rm, cm + 1, t.c1});
        if (rm + 1 <= t.r1) out.push_back({rm + 1, t.r1, t.c0, cm});
        if (rm + 1 <= t.r1 && cm + 1 <= t.c1) out.push_back({rm + 1, t.r1, cm + 1, t.c1});
        return out;
    }

    void classify_nodes(const Tile& tile, const vector<int>& frontier, Moment2& full,
                        vector<int>& boundary_nodes, bool collect_root_stats) {
        Bounds tb = grid_.tile_bounds(tile);
        vector<int> stack = frontier;
        while (!stack.empty()) {
            int idx = stack.back();
            stack.pop_back();
            const Node& n = tree_.nodes[idx];
            if (min_dist_mbr(n.box, tb) > h_) {
                counters_.empty_nodes++;
                if (collect_root_stats) {
                    counters_.root_empty_leaf_nodes += n.leaf_count;
                    counters_.root_empty_points += n.moment.count;
                }
                continue;
            }
            if (params_.variant != 1 && max_dist_mbr(n.box, tb) <= h_) {
                full.add(n.moment);
                counters_.full_nodes++;
                if (collect_root_stats) {
                    counters_.root_full_leaf_nodes += n.leaf_count;
                    counters_.root_full_points += n.moment.count;
                }
                continue;
            }
            if (n.is_leaf()) {
                boundary_nodes.push_back(idx);
                counters_.boundary_nodes++;
                counters_.boundary_points += n.moment.count;
                if (collect_root_stats) {
                    counters_.root_boundary_leaf_nodes++;
                    counters_.root_boundary_points += n.moment.count;
                }
            } else {
                stack.push_back(n.left);
                stack.push_back(n.right);
            }
        }
    }

    void solve_tile(const Tile& tile, const Moment2& inherited_full, const vector<int>& frontier) {
        Moment2 full = inherited_full;
        vector<int> boundary_nodes;
        bool collect_root_stats = !root_stats_recorded_ && frontier.size() == 1 && frontier[0] == 0 &&
                                  tile.r0 == 0 && tile.r1 == grid_.rows - 1 &&
                                  tile.c0 == 0 && tile.c1 == grid_.cols - 1;
        classify_nodes(tile, frontier, full, boundary_nodes, collect_root_stats);
        if (collect_root_stats) {
            root_stats_recorded_ = true;
        }

        long long boundary_count = 0;
        for (int idx : boundary_nodes) {
            boundary_count += tree_.nodes[idx].moment.count;
        }
        long long estimated_work = boundary_count * tile_pixels(tile);
        bool can_split = params_.variant != 2 &&
                         (tile_rows(tile) > params_.min_tile_side || tile_cols(tile) > params_.min_tile_side);
        if (can_split && estimated_work > params_.split_work_limit) {
            counters_.split_tiles++;
            for (const Tile& child : split_tile(tile)) {
                solve_tile(child, full, boundary_nodes);
            }
            return;
        }
        counters_.evaluated_tiles++;
        evaluate_tile(tile, full, boundary_nodes);
    }

    void evaluate_tile(const Tile& tile, const Moment2& full, const vector<int>& boundary_nodes) {
        if (params_.collect_work_stats) {
            long long pixels = tile_pixels(tile);
            long long boundary_count = 0;
            for (int idx : boundary_nodes) {
                boundary_count += tree_.nodes[idx].moment.count;
            }
            long long full_count = full.count;
            long long total_points = static_cast<long long>(tree_.points.size());
            long long empty_count = max(0LL, total_points - full_count - boundary_count);
            counters_.full_work_aggregated += pixels * full_count;
            counters_.boundary_work_scanned += pixels * boundary_count;
            counters_.empty_work_pruned += pixels * empty_count;
            counters_.total_potential_work += pixels * total_points;
        }

        for (int r = tile.r0; r <= tile.r1; r++) {
            for (int c = tile.c0; c <= tile.c1; c++) {
                Point q = grid_.at(r, c);
                double value = full_kernel_value(full, q, h_, params_.kernel_type);
                for (int idx : boundary_nodes) {
                    const Node& n = tree_.nodes[idx];
                    for (int pos = n.begin; pos < n.end; pos++) {
                        const Point& p = tree_.points[tree_.order[pos]];
                        double dx = q.x - p.x;
                        double dy = q.y - p.y;
                        double d2 = dx * dx + dy * dy;
                        counters_.direct_point_pixel_tests++;
                        if (d2 <= h_ * h_) {
                            value += point_kernel_value(d2, h_, params_.kernel_type);
                        }
                    }
                }
                values_[static_cast<size_t>(r) * grid_.cols + c] = value;
            }
        }
    }
};

