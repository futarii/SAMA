#pragma once

#include "common.h"
static GridInfo make_grid(const Dataset& ds, int rows, int cols) {
    GridInfo grid;
    grid.rows = rows;
    grid.cols = cols;
    grid.box = ds.box;
    grid.incr_x = rows > 1 ? (ds.box.xmax - ds.box.xmin) / (rows - 1) : 0.0;
    grid.incr_y = cols > 1 ? (ds.box.ymax - ds.box.ymin) / (cols - 1) : 0.0;
    return grid;
}

static void write_values(const string& path, const GridInfo& grid, const vector<double>& values) {
    ofstream out(path);
    if (!out) {
        throw runtime_error("cannot write values: " + path);
    }
    out << setprecision(12);
    for (int r = 0; r < grid.rows; r++) {
        for (int c = 0; c < grid.cols; c++) {
            Point q = grid.at(r, c);
            out << q.x << " " << q.y << " " << values[static_cast<size_t>(r) * grid.cols + c] << "\n";
        }
    }
}

static vector<double> read_values_only(const string& path, int expected) {
    ifstream in(path);
    if (!in) {
        throw runtime_error("cannot open values: " + path);
    }
    vector<double> values;
    values.reserve(expected);
    double x, y, v;
    while (in >> x >> y >> v) {
        values.push_back(v);
    }
    if (static_cast<int>(values.size()) != expected) {
        stringstream ss;
        ss << "expected " << expected << " values from " << path << ", got " << values.size();
        throw runtime_error(ss.str());
    }
    return values;
}

static unsigned char clamp_byte(double v) {
    if (v < 0.0) return 0;
    if (v > 255.0) return 255;
    return static_cast<unsigned char>(v + 0.5);
}

static void parse_hex_color(const char* hex, unsigned char& r, unsigned char& g, unsigned char& b) {
    auto val = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return 10 + c - 'a';
        if (c >= 'A' && c <= 'F') return 10 + c - 'A';
        return 0;
    };
    r = static_cast<unsigned char>(val(hex[1]) * 16 + val(hex[2]));
    g = static_cast<unsigned char>(val(hex[3]) * 16 + val(hex[4]));
    b = static_cast<unsigned char>(val(hex[5]) * 16 + val(hex[6]));
}

static void coreset_threshold_color(double percent, unsigned char& r, unsigned char& g, unsigned char& b) {
    static const char* colors[] = {
        "#f7f4f9", "#00d0e5", "#0089e1", "#0044dd", "#0001d9", "#3e00d5",
        "#7b00d2", "#b700ce", "#ca44a3", "#c60065", "#c24429"
    };
    static const double domain[] = {0.05, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95};
    percent = max(0.0, min(1.0, percent));
    int idx = 0;
    while (idx < 10 && percent > domain[idx]) {
        idx++;
    }
    parse_hex_color(colors[idx], r, g, b);
}

static void write_ppm(const string& path, int rows, int cols, const vector<double>& values,
                      double min_v, double max_v, bool absolute = false) {
    ofstream out(path, ios::binary);
    if (!out) {
        throw runtime_error("cannot write ppm: " + path);
    }
    int out_width = rows;
    int out_height = cols;
    out << "P6\n" << out_width << " " << out_height << "\n255\n";
    double range = max(max_v - min_v, 1e-12);
    for (int out_y = 0; out_y < out_height; out_y++) {
        for (int out_x = 0; out_x < out_width; out_x++) {
            int src_r = out_x;
            int src_c = cols - 1 - out_y;
            double v = values[static_cast<size_t>(src_r) * cols + src_c];
            if (absolute) v = fabs(v);
            double percent = (v - min_v) / range;
            unsigned char rr, gg, bb;
            coreset_threshold_color(percent, rr, gg, bb);
            out.write(reinterpret_cast<char*>(&rr), 1);
            out.write(reinterpret_cast<char*>(&gg), 1);
            out.write(reinterpret_cast<char*>(&bb), 1);
        }
    }
}

static void write_html_viewer(const string& path, const string& title,
                              const string& a_img, const string& b_img, const string& diff_img) {
    ofstream out(path);
    if (!out) {
        throw runtime_error("cannot write html: " + path);
    }
    out << "<!doctype html><meta charset=\"utf-8\"><title>" << title << "</title>\n";
    out << "<style>body{font-family:Arial,sans-serif;margin:24px;background:#f7f7f7;color:#222}"
           ".grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}"
           ".panel{background:white;border:1px solid #ddd;padding:12px}"
           "img{width:100%;image-rendering:pixelated}.cap{font-weight:700;margin-bottom:8px}</style>\n";
    out << "<h2>" << title << "</h2><div class=\"grid\">";
    out << "<div class=\"panel\"><div class=\"cap\">SBD-KDV</div><img src=\"" << a_img << "\"></div>";
    out << "<div class=\"panel\"><div class=\"cap\">SLAM_BUCKET^RAO</div><img src=\"" << b_img << "\"></div>";
    out << "<div class=\"panel\"><div class=\"cap\">Absolute Difference</div><img src=\"" << diff_img << "\"></div>";
    out << "</div>\n";
}

