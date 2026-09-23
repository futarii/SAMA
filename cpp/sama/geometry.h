#pragma once

#include "common.h"
static double min_dist_mbr(const Bounds& a, const Bounds& b) {
    double dx = 0.0;
    if (a.xmax < b.xmin) dx = b.xmin - a.xmax;
    else if (b.xmax < a.xmin) dx = a.xmin - b.xmax;
    double dy = 0.0;
    if (a.ymax < b.ymin) dy = b.ymin - a.ymax;
    else if (b.ymax < a.ymin) dy = a.ymin - b.ymax;
    return sqrt(dx * dx + dy * dy);
}

static double max_dist_mbr(const Bounds& a, const Bounds& b) {
    double dx = max(fabs(a.xmin - b.xmin), fabs(a.xmin - b.xmax));
    dx = max(dx, fabs(a.xmax - b.xmin));
    dx = max(dx, fabs(a.xmax - b.xmax));
    double dy = max(fabs(a.ymin - b.ymin), fabs(a.ymin - b.ymax));
    dy = max(dy, fabs(a.ymax - b.ymin));
    dy = max(dy, fabs(a.ymax - b.ymax));
    return sqrt(dx * dx + dy * dy);
}

