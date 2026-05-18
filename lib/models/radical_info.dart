class RadicalInfo {
  final String? left;
  final String? right;

  const RadicalInfo({this.left, this.right});

  bool get hasDecomposition => left != null && right != null;
}
