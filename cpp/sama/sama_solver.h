#pragma once

#include "geometry.h"
#include "kd_tree.h"
#include "kernel.h"

class SbdSolver2 {
public:
    SbdSolver2(const Tree2& tree, GridInfo grid, double bandwidth, const SbdParams& params);
    SbdResult run();

private:
    const Tree2& tree_;
    GridInfo grid_;
    double h_ = 0.0;
    SbdParams params_;
    vector<double> values_;
    Counters counters_;
    bool root_stats_recorded_ = false;

    int tile_rows(const Tile& t) const;
    int tile_cols(const Tile& t) const;
    long long tile_pixels(const Tile& t) const;
    vector<Tile> split_tile(const Tile& t) const;
    void classify_nodes(const Tile& tile, const vector<int>& frontier, Moment2& full,
                        vector<int>& boundary_nodes, bool collect_root_stats);
    void solve_tile(const Tile& tile, const Moment2& inherited_full, const vector<int>& frontier);
    void evaluate_tile(const Tile& tile, const Moment2& full, const vector<int>& boundary_nodes);
};
