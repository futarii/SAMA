#pragma once

#include "common.h"

struct Tree2 {
    vector<Point> points;
    vector<int> order;
    vector<Node> nodes;
    int leaf_capacity = 64;
};

int build_tree2(Tree2& tree, int begin, int end);
