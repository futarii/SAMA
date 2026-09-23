#pragma once

#include "dataset_io.h"
#include "kd_tree.h"
#include "output_io.h"
#include "sama_solver.h"
static int cmd_prepare(int argc, char** argv) {
    if (argc != 4) {
        cerr << "usage: kdv_experiment prepare raw_dataset header_dataset\n";
        return 2;
    }
    Dataset ds = load_dataset(argv[2]);
    write_header_dataset(ds, argv[3]);
    cout << "points=" << ds.points.size() << " wrote=" << argv[3] << "\n";
    return 0;
}

static int cmd_sbd(int argc, char** argv) {
    if (argc < 7) {
        cerr << "usage: kdv_experiment sbd dataset out_values out_ppm rows cols [b_factor=1] [min_tile=8] [leaf=64] [work=200000] [kernel=1] [variant=0] [qxmin qxmax qymin qymax] [--collect-work]\n";
        cerr << "kernel: 0=Uniform, 1=Epanechnikov, 2=Quartic\n";
        cerr << "variant: 0=full SAMA, 1=no full-cover aggregation, 2=no tile splitting\n";
        return 2;
    }
    string dataset_path = argv[2];
    string out_values = argv[3];
    string out_ppm = argv[4];
    SbdParams params;
    params.rows = atoi(argv[5]);
    params.cols = atoi(argv[6]);
    vector<string> opt;
    for (int i = 7; i < argc; i++) {
        string arg = argv[i];
        if (arg == "--collect-work" || arg == "--collect-work=1" || arg == "collect_work=1") {
            params.collect_work_stats = true;
        } else {
            opt.push_back(arg);
        }
    }
    if (opt.size() > 0) params.bandwidth_factor = atof(opt[0].c_str());
    if (opt.size() > 1) params.min_tile_side = atoi(opt[1].c_str());
    if (opt.size() > 2) params.leaf_capacity = atoi(opt[2].c_str());
    if (opt.size() > 3) params.split_work_limit = atoll(opt[3].c_str());
    if (opt.size() > 4) params.kernel_type = atoi(opt[4].c_str());
    if (opt.size() == 6 || opt.size() >= 10) {
        params.variant = atoi(opt[5].c_str());
    }
    if (opt.size() == 9) {
        params.has_query_box = true;
        params.query_box.xmin = atof(opt[5].c_str());
        params.query_box.xmax = atof(opt[6].c_str());
        params.query_box.ymin = atof(opt[7].c_str());
        params.query_box.ymax = atof(opt[8].c_str());
    }
    if (opt.size() >= 10) {
        params.has_query_box = true;
        params.query_box.xmin = atof(opt[6].c_str());
        params.query_box.xmax = atof(opt[7].c_str());
        params.query_box.ymin = atof(opt[8].c_str());
        params.query_box.ymax = atof(opt[9].c_str());
    }
    if (params.kernel_type < 0 || params.kernel_type > 2) {
        throw runtime_error("kernel must be 0=Uniform, 1=Epanechnikov, or 2=Quartic");
    }
    if (params.variant < 0 || params.variant > 2) {
        throw runtime_error("variant must be 0=full SAMA, 1=no full-cover, or 2=no tile split");
    }

    Dataset ds = load_dataset(dataset_path);
    double origin_x = ds.box.xmin;
    double origin_y = ds.box.ymin;
    translate_to_origin(ds);
    GridInfo grid = make_grid(ds, params.rows, params.cols);
    if (params.has_query_box) {
        grid.box = translated_box(params.query_box, origin_x, origin_y);
        grid.incr_x = params.rows > 1 ? (grid.box.xmax - grid.box.xmin) / (params.rows - 1) : 0.0;
        grid.incr_y = params.cols > 1 ? (grid.box.ymax - grid.box.ymin) / (params.cols - 1) : 0.0;
    }
    double h = scott_bandwidth(ds.points, params.bandwidth_factor);

    Tree2 tree;
    tree.points = ds.points;
    tree.leaf_capacity = params.leaf_capacity;
    tree.order.resize(tree.points.size());
    for (int i = 0; i < static_cast<int>(tree.order.size()); i++) tree.order[i] = i;
    auto build_start = chrono::high_resolution_clock::now();
    build_tree2(tree, 0, static_cast<int>(tree.order.size()));
    auto build_end = chrono::high_resolution_clock::now();
    double build_seconds = chrono::duration_cast<chrono::duration<double>>(build_end - build_start).count();

    SbdSolver2 solver(tree, grid, h, params);
    SbdResult result = solver.run();
    double solve_seconds = result.seconds;
    double total_compute_seconds = build_seconds + solve_seconds;
    if (out_values != "-") {
        write_values(out_values, grid, result.values);
    }
    if (out_ppm != "-") {
        auto minmax_v = minmax_element(result.values.begin(), result.values.end());
        write_ppm(out_ppm, params.rows, params.cols, result.values, *minmax_v.first, *minmax_v.second);
    }

    cout << fixed << setprecision(6);
    cout << "method=SBD_KDV"
         << " points=" << ds.points.size()
         << " rows=" << params.rows
         << " cols=" << params.cols
         << " kernel=" << params.kernel_type
         << " variant=" << params.variant
         << " bandwidth=" << result.bandwidth
         << " seconds=" << total_compute_seconds
         << " build_seconds=" << build_seconds
         << " solve_seconds=" << solve_seconds
         << " tree_nodes=" << tree.nodes.size()
         << " full_nodes=" << result.counters.full_nodes
         << " empty_nodes=" << result.counters.empty_nodes
         << " boundary_nodes=" << result.counters.boundary_nodes
         << " boundary_points_seen=" << result.counters.boundary_points
         << " root_full_leaf_nodes=" << result.counters.root_full_leaf_nodes
         << " root_empty_leaf_nodes=" << result.counters.root_empty_leaf_nodes
         << " root_boundary_leaf_nodes=" << result.counters.root_boundary_leaf_nodes
         << " root_full_points=" << result.counters.root_full_points
         << " root_empty_points=" << result.counters.root_empty_points
         << " root_boundary_points=" << result.counters.root_boundary_points
         << " split_tiles=" << result.counters.split_tiles
         << " evaluated_tiles=" << result.counters.evaluated_tiles
         << " point_pixel_tests=" << result.counters.direct_point_pixel_tests
         << " full_work_aggregated=" << result.counters.full_work_aggregated
         << " boundary_work_scanned=" << result.counters.boundary_work_scanned
         << " empty_work_pruned=" << result.counters.empty_work_pruned
         << " total_potential_work=" << result.counters.total_potential_work
         << "\n";
    return 0;
}

static int cmd_compare(int argc, char** argv) {
    if (argc != 11) {
        cerr << "usage: kdv_experiment compare sbd_values slam_values rows cols sbd_ppm slam_ppm diff_ppm viewer_html title\n";
        return 2;
    }
    string sbd_path = argv[2];
    string slam_path = argv[3];
    int rows = atoi(argv[4]);
    int cols = atoi(argv[5]);
    string sbd_ppm = argv[6];
    string slam_ppm = argv[7];
    string diff_ppm = argv[8];
    string viewer = argv[9];
    string title = argv[10];

    int n = rows * cols;
    vector<double> sbd = read_values_only(sbd_path, n);
    vector<double> slam = read_values_only(slam_path, n);
    vector<double> diff(n);
    double max_abs = 0.0;
    double sum_sq = 0.0;
    double sum_abs = 0.0;
    for (int i = 0; i < n; i++) {
        diff[i] = sbd[i] - slam[i];
        double a = fabs(diff[i]);
        max_abs = max(max_abs, a);
        sum_abs += a;
        sum_sq += diff[i] * diff[i];
    }
    auto minmax_sbd = minmax_element(sbd.begin(), sbd.end());
    auto minmax_slam = minmax_element(slam.begin(), slam.end());
    double lo = min(*minmax_sbd.first, *minmax_slam.first);
    double hi = max(*minmax_sbd.second, *minmax_slam.second);
    write_ppm(sbd_ppm, rows, cols, sbd, lo, hi);
    write_ppm(slam_ppm, rows, cols, slam, lo, hi);
    write_ppm(diff_ppm, rows, cols, diff, 0.0, max_abs, true);
    write_html_viewer(viewer, title, sbd_ppm, slam_ppm, diff_ppm);

    cout << fixed << setprecision(9);
    cout << "rmse=" << sqrt(sum_sq / n)
         << " mae=" << (sum_abs / n)
         << " max_abs=" << max_abs
         << " shared_min=" << lo
         << " shared_max=" << hi
         << "\n";
    return 0;
}

