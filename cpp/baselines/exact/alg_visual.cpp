#include "alg_visual.h"

inline void clearHeap(PQ& pq)
{
	int heapSize = (int)pq.size();
	for (int h = 0; h < heapSize; h++)
		pq.pop();
}

void GBF_iter(Tree& tree, statistics& stat)
{
	static PQ pq;
	pqNode pq_entry;
	Node*curNode;
	double L, U;
	double f_cur;
	double val_R;

	Node*rootNode = tree.rootNode;
	double*cur_q = stat.queryVector[stat.cur_r*stat.n_col + stat.cur_c];
	stat.q_SquareNorm = computeSqNorm(cur_q, stat.dim);
	unsigned long long query_nodes_popped = 0;
	unsigned long long query_max_pq_size = 0;
	bool collect_akde_diag = stat.diagnostics_enabled && stat.method == 1;
	if (collect_akde_diag)
		stat.akde_queries++;

	if (stat.method >= 1 && stat.method <= 2)
	{
		L = rootNode->LB(cur_q, stat);
		U = rootNode->UB(cur_q, stat);
	}

	pq_entry.node = rootNode;
	pq_entry.node_L = L;
	pq_entry.node_U = U;
	pq_entry.discrepancy = U - L;

	pq.push(pq_entry);
	query_max_pq_size = max(query_max_pq_size, (unsigned long long)pq.size());

	while (pq.size() != 0)
	{
		if (collect_akde_diag)
			stat.akde_validate_checks++;
		if (validate_best(L, U, stat.epsilon, val_R) == true)
		{
			stat.out_visual[stat.cur_r][stat.cur_c] = val_R;
			if (collect_akde_diag)
			{
				stat.akde_early_stops++;
				if (query_nodes_popped == 0)
					stat.akde_root_stops++;
				stat.akde_nodes_popped += query_nodes_popped;
				stat.akde_sum_max_pq_size += query_max_pq_size;
				stat.akde_max_pq_size = max(stat.akde_max_pq_size, query_max_pq_size);
			}
			clearHeap(pq);
			return;
		}

		pq_entry = pq.top();
		pq.pop();
		query_nodes_popped++;

		L = L - pq_entry.node_L;
		U = U - pq_entry.node_U;

		curNode = pq_entry.node;

		//leaf Node
		if ((int)curNode->idList.size() <= tree.leafCapacity)
		{
			if (collect_akde_diag)
			{
				stat.akde_leaf_refinements++;
				stat.akde_leaf_points_refined += curNode->idList.size();
			}
			f_cur = refinement(curNode, stat);
			L = L + f_cur;
			U = U + f_cur;

			continue;
		}

		//Non-Leaf Node
		if (collect_akde_diag)
			stat.akde_internal_expansions++;
		for (int c = 0; c < (int)curNode->childVector.size(); c++)
		{
			pq_entry.node_L = curNode->childVector[c]->LB(cur_q, stat);
			pq_entry.node_U = curNode->childVector[c]->UB(cur_q, stat);

			pq_entry.discrepancy = pq_entry.node_U - pq_entry.node_L;
			pq_entry.node = curNode->childVector[c];

			L = L + pq_entry.node_L;
			U = U + pq_entry.node_U;

			pq.push(pq_entry);
			if (collect_akde_diag)
			{
				stat.akde_child_pushes++;
				query_max_pq_size = max(query_max_pq_size, (unsigned long long)pq.size());
			}
		}
	}

	stat.out_visual[stat.cur_r][stat.cur_c] = L;
	if (collect_akde_diag)
	{
		stat.akde_nodes_popped += query_nodes_popped;
		stat.akde_sum_max_pq_size += query_max_pq_size;
		stat.akde_max_pq_size = max(stat.akde_max_pq_size, query_max_pq_size);
	}
	clearHeap(pq);
}

void visual_Algorithm(statistics& stat)
{
	double run_time;
	//Different algorithms
	auto start_s = chrono::high_resolution_clock::now();

	//Preprocessing stage for indexing framework
	kdTree kd_Tree(stat.dim, stat.featureVector, stat.leafCapacity);
	ballTree ball_Tree(stat.dim, stat.featureVector, stat.leafCapacity);

	if (stat.method == 1 || stat.method == 2 || stat.method == 3)
	{
		if (stat.method == 1 || stat.method == 3) //aKDE (LB_MBR and UB_MBR), RQS_kd
			kd_Tree.rootNode = new kdNode();
		if (stat.method == 2) //QUAD (LB_QUAD and UB_QUAD)
			kd_Tree.rootNode = new kdQuadAugNode();
		if (stat.method == 3) //RQS_kd
			kd_Tree.init_RQS(stat);

		kd_Tree.build_kdTree(stat);
		kd_Tree.updateAugment((kdNode*)kd_Tree.rootNode);
	}
	if (stat.method == 4) //RQS_ball
	{
		ball_Tree.rootNode = new ballNode();
		ball_Tree.build_ballTree(stat);
	}

	//Online stage
	if (stat.method == 0) //SCAN method
		KDE_visual(stat);

	if (stat.method >= 1 && stat.method <= 4) //aKDE, QUAD, RQS_kd and RQS_ball methods
	{
		for (int r = 0; r < stat.n_row; r++)
		{
			stat.cur_r = r;
			for (int c = 0; c < stat.n_col; c++)
			{
				stat.cur_c = c;
				if (stat.method == 1 || stat.method == 2)
					GBF_iter(kd_Tree, stat);
				if (stat.method == 3)
					kd_Tree.RQS(stat);
				if (stat.method == 4)
					ball_Tree.RQS(stat);
			}
		}
	}

	//SLAM_SORT and SLAM_BUCKET
	if (stat.method == 5 || stat.method == 6 || stat.method == 7 || stat.method == 8) 
		SLAM_visual(stat);

	auto end_s = chrono::high_resolution_clock::now();

	run_time = (chrono::duration_cast<chrono::nanoseconds>(end_s - start_s).count()) / 1000000000.0;
	std::cout << "method " << stat.method << ":" << run_time << endl;
	if (stat.diagnostics_enabled && stat.method == 1)
	{
		double queries = max(1.0, (double)stat.akde_queries);
		std::cout << "diagnostics method 1"
			<< " queries=" << stat.akde_queries
			<< " early_stops=" << stat.akde_early_stops
			<< " root_stops=" << stat.akde_root_stops
			<< " nodes_popped=" << stat.akde_nodes_popped
			<< " internal_expansions=" << stat.akde_internal_expansions
			<< " child_pushes=" << stat.akde_child_pushes
			<< " leaf_refinements=" << stat.akde_leaf_refinements
			<< " leaf_points_refined=" << stat.akde_leaf_points_refined
			<< " validate_checks=" << stat.akde_validate_checks
			<< " avg_nodes_popped=" << (double)stat.akde_nodes_popped / queries
			<< " avg_leaf_refinements=" << (double)stat.akde_leaf_refinements / queries
			<< " avg_leaf_points_refined=" << (double)stat.akde_leaf_points_refined / queries
			<< " avg_max_pq_size=" << (double)stat.akde_sum_max_pq_size / queries
			<< " max_pq_size=" << stat.akde_max_pq_size
			<< endl;
	}

	output_visual(stat);
}
