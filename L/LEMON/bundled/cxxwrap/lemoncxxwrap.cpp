#include "jlcxx/jlcxx.hpp"

#include <lemon/list_graph.h>
#include <lemon/dijkstra.h>
#include <lemon/matching.h>
#include <lemon/network_simplex.h>

#include <cstdint>
#include <functional>

using namespace lemon;
using namespace std;

std::string compiledebug()
{
   return "baseline compilation works";
}

template<typename IntT>
void register_network_simplex_type(jlcxx::Module& mod, const char* type_name)
{
  using NetworkSimplexT = NetworkSimplex<ListDigraph, IntT, IntT>;
  mod.add_type<NetworkSimplexT>(type_name)
    .constructor<const ListDigraph&>()
    .method("lowerMap", [](NetworkSimplexT& ns, const ListDigraph::ArcMap<IntT>& map) -> NetworkSimplexT& { return ns.lowerMap(map); })
    .method("upperMap", [](NetworkSimplexT& ns, const ListDigraph::ArcMap<IntT>& map) -> NetworkSimplexT& { return ns.upperMap(map); })
    .method("costMap", [](NetworkSimplexT& ns, const ListDigraph::ArcMap<IntT>& map) -> NetworkSimplexT& { return ns.costMap(map); })
    .method("supplyMap", [](NetworkSimplexT& ns, const ListDigraph::NodeMap<IntT>& map) -> NetworkSimplexT& { return ns.supplyMap(map); })
    .method("stSupply", &NetworkSimplexT::stSupply)
    .method("reset", &NetworkSimplexT::reset)
    .method("resetParams", &NetworkSimplexT::resetParams)
    .method("run", [](NetworkSimplexT& ns) { return static_cast<int>(ns.run()); })
    .method("totalCost", static_cast<IntT (NetworkSimplexT::*)() const>(&NetworkSimplexT::totalCost))
    .method("flow", &NetworkSimplexT::flow)
    .method("potential", &NetworkSimplexT::potential);
}

namespace jlcxx
{
  template<> struct SuperType<ListGraph::NodeIt> { typedef ListGraph::Node type; };
  template<> struct SuperType<ListGraph::EdgeIt> { typedef ListGraph::Edge type; };
  template<> struct SuperType<ListDigraph::NodeIt> { typedef ListDigraph::Node type; };
  // no appropriate factory error
  //template<> struct SuperType<ListDigraph::ArcIt> { typedef ListDigraph::Arc type; };
}

JLCXX_MODULE define_julia_module(jlcxx::Module& mod)
{
  mod.method("compiledebug", &compiledebug);

  mod.add_type<ListGraph::Node>("ListGraphNode");
  mod.add_type<ListDigraph::Node>("ListDigraphNode");
  mod.add_type<ListGraph::Edge>("ListGraphEdge");
  mod.add_type<ListGraph::Arc>("ListGraphArc");
  mod.add_type<ListDigraph::Arc>("ListDigraphArc");

  mod.method("id", static_cast<int(*)(ListGraph::Node)>(&ListGraph::id));
  mod.method("id", static_cast<int(*)(ListGraph::Edge)>(&ListGraph::id));
  mod.method("id", static_cast<int(*)(ListGraph::Arc)>(&ListGraph::id));
  mod.method("id", static_cast<int(*)(ListDigraph::Node)>(&ListDigraph::id));
  mod.method("id", static_cast<int(*)(ListDigraph::Arc)>(&ListDigraph::id));

  mod.add_type<ListGraph>("ListGraph")
    .method("addNode"  , &ListGraph::addNode)
    .method("addEdge"  , &ListGraph::addEdge)
    .method("u", [](const ListGraph& g, const ListGraph::Edge& e) { return g.u(e); })
    .method("v", [](const ListGraph& g, const ListGraph::Edge& e) { return g.v(e); });
  mod.add_type<ListDigraph>("ListDigraph")
    .method("addNode"  , &ListDigraph::addNode)
    .method("addArc"   , &ListDigraph::addArc)
    .method("source", [](const ListDigraph& g, const ListDigraph::Arc& a) { return g.source(a); })
    .method("target", [](const ListDigraph& g, const ListDigraph::Arc& a) { return g.target(a); });

  mod.add_type<ListGraph::NodeIt>("ListGraphNodeIt", jlcxx::julia_base_type<ListGraph::Node>())
    .constructor<const ListGraph&>()
    .method("iternext", &ListGraph::NodeIt::operator++);
  mod.add_type<ListDigraph::NodeIt>("ListDigraphNodeIt", jlcxx::julia_base_type<ListDigraph::Node>())
    .constructor<const ListDigraph&>()
    .method("iternext", &ListDigraph::NodeIt::operator++);
  mod.add_type<ListGraph::EdgeIt>("ListGraphEdgeIt", jlcxx::julia_base_type<ListGraph::Edge>())
    .constructor<const ListGraph&>()
    .method("iternext", &ListGraph::EdgeIt::operator++);
  // no appropriate factory error
  //mod.add_type<ListDigraph::ArcIt>("ListDigraphArcIt", jlcxx::julia_base_type<ListDigraph::ArcIt>())
  //  .constructor<const ListDigraph&>()
  //  .method("iternext", &ListDigraph::ArcIt::operator++);

  mod.add_type<ListGraph::NodeMap<int>>("ListGraphNodeMapInt")
    .constructor<const ListGraph&>()
    .method("set", &ListGraph::NodeMap<int>::set)
    .method("get", [](const ListGraph::NodeMap<int>& m, const ListGraph::Node& n) { return m[n]; });
  mod.add_type<ListDigraph::NodeMap<int>>("ListDigraphNodeMapInt")
    .constructor<const ListDigraph&>()
    .method("set", &ListDigraph::NodeMap<int>::set)
    .method("get", [](const ListDigraph::NodeMap<int>& m, const ListDigraph::Node& n) { return m[n]; });
  mod.add_type<ListGraph::EdgeMap<int>>("ListGraphEdgeMapInt")
    .constructor<const ListGraph&>()
    .method("set", &ListGraph::EdgeMap<int>::set)
    .method("get", [](const ListGraph::EdgeMap<int>& m, const ListGraph::Edge& e) { return m[e]; });
  mod.add_type<ListDigraph::ArcMap<int>>("ListDigraphArcMapInt")
    .constructor<const ListDigraph&>()
    .method("set", &ListDigraph::ArcMap<int>::set)
    .method("get", [](const ListDigraph::ArcMap<int>& m, const ListDigraph::Arc& a) { return m[a]; });

  mod.method("ListGraphNodeFromId", [](int i) { return ListGraph::nodeFromId(i); });
  mod.method("ListGraphEdgeFromId", [](int i) { return ListGraph::edgeFromId(i); });
  mod.method("ListDigraphNodeFromId", [](int i) { return ListDigraph::nodeFromId(i); });
  mod.method("ListDigraphArcFromId", [](int i) { return ListDigraph::arcFromId(i); });

  using DijkstraInt = Dijkstra<ListDigraph, ListDigraph::ArcMap<int>>;
  using DijkstraRunS = void (DijkstraInt::*)(ListDigraph::Node);
  using DijkstraRunST = bool (DijkstraInt::*)(ListDigraph::Node, ListDigraph::Node);
  DijkstraRunS dijkstra_run_s = &DijkstraInt::run;
  DijkstraRunST dijkstra_run_st = &DijkstraInt::run;
  mod.add_type<DijkstraInt>("DijkstraListDigraphArcMapInt")
    .constructor<const ListDigraph&, const ListDigraph::ArcMap<int>&>()
    .method("run", dijkstra_run_s)
    .method("run", dijkstra_run_st)
    .method("dist", &DijkstraInt::dist)
    .method("predNode", &DijkstraInt::predNode)
    .method("predArc", &DijkstraInt::predArc)
    .method("reached", &DijkstraInt::reached);

  using MWPM = MaxWeightedPerfectMatching<ListGraph, ListGraph::EdgeMap<int>>;
  using MWPMmatchingedge_ptr = bool (MWPM::*)(const ListGraph::Edge&) const; // used to resolve the overloads of `matching`
  using MWPMmatchingnode_ptr = ListGraph::Arc (MWPM::*)(const ListGraph::Node&) const; // used to resolve the overloads of `matching`
  MWPMmatchingedge_ptr matchingedge = &MWPM::matching;
  MWPMmatchingnode_ptr matchingnode = &MWPM::matching;
  mod.add_type<MWPM>("MaxWeightedPerfectMatchingListGraphInt")
    .constructor<const ListGraph&, const ListGraph::EdgeMap<int>&>()
    .method("mate", &MWPM::mate)
    .method("run", &MWPM::run)
    .method("matchingWeight", &MWPM::matchingWeight)
    .method("matching", matchingedge)
    .method("matching", matchingnode)
    .method("dualValue", &MWPM::dualValue)
    .method("nodeValue", &MWPM::nodeValue)
    .method("blossomNum", &MWPM::blossomNum)
    .method("blossomSize", &MWPM::blossomSize)
    .method("blossomValue", &MWPM::blossomValue);

  register_network_simplex_type<int>(mod, "NetworkSimplexListDigraphIntInt");
  register_network_simplex_type<std::int64_t>(mod, "NetworkSimplexListDigraphInt64Int64");

  using NetworkSimplexProblemTypes = NetworkSimplex<ListDigraph, int, int>;
  mod.method("NetworkSimplexProblemTypeInfeasible", []() { return static_cast<int>(NetworkSimplexProblemTypes::INFEASIBLE); });
  mod.method("NetworkSimplexProblemTypeOptimal", []() { return static_cast<int>(NetworkSimplexProblemTypes::OPTIMAL); });
  mod.method("NetworkSimplexProblemTypeUnbounded", []() { return static_cast<int>(NetworkSimplexProblemTypes::UNBOUNDED); });
}
