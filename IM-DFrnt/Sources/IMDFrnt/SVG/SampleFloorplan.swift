import Foundation

/// `Sample/sample-floorplan.svg`와 같은 내용을 실행 파일에 직접 넣었다.
/// SPM 리소스 번들 경로에 의존하지 않으므로 `swift run`과 `.app` 양쪽에서 동일하게 동작한다.
enum SampleFloorplan {
    static let name = "sample-floorplan.svg"
    static let svg: String =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1000 700\" width=\"1000\" height=\"700\">\n" +
    "  <!-- IM-DFrnt 테스트 도면: 방 / 문 / 곡선 개체를 고루 포함한다 -->\n" +
    "\n" +
    "  <g id=\"walls\" stroke=\"#2b2b30\" stroke-width=\"3\" fill=\"none\">\n" +
    "    <path d=\"M 60 60 L 940 60 L 940 640 L 60 640 Z\"/>\n" +
    "    <path d=\"M 60 300 L 420 300\"/>\n" +
    "    <path d=\"M 420 60 L 420 640\"/>\n" +
    "    <path d=\"M 700 300 L 940 300\"/>\n" +
    "    <path d=\"M 700 60 L 700 640\"/>\n" +
    "  </g>\n" +
    "\n" +
    "  <g id=\"rooms\" stroke=\"#3a6ea5\" stroke-width=\"2\" fill=\"none\">\n" +
    "    <rect x=\"80\" y=\"80\" width=\"320\" height=\"200\"/>\n" +
    "    <rect x=\"80\" y=\"320\" width=\"320\" height=\"300\"/>\n" +
    "    <rect x=\"440\" y=\"80\" width=\"240\" height=\"540\"/>\n" +
    "    <rect x=\"720\" y=\"80\" width=\"200\" height=\"200\"/>\n" +
    "    <rect x=\"720\" y=\"320\" width=\"200\" height=\"300\"/>\n" +
    "  </g>\n" +
    "\n" +
    "  <g id=\"doors\" stroke=\"#c25a3b\" stroke-width=\"4\" fill=\"none\">\n" +
    "    <line x1=\"230\" y1=\"300\" x2=\"290\" y2=\"300\"/>\n" +
    "    <line x1=\"420\" y1=\"180\" x2=\"420\" y2=\"240\"/>\n" +
    "    <line x1=\"420\" y1=\"420\" x2=\"420\" y2=\"480\"/>\n" +
    "    <line x1=\"700\" y1=\"160\" x2=\"700\" y2=\"220\"/>\n" +
    "    <line x1=\"700\" y1=\"440\" x2=\"700\" y2=\"500\"/>\n" +
    "    <line x1=\"820\" y1=\"300\" x2=\"880\" y2=\"300\"/>\n" +
    "  </g>\n" +
    "\n" +
    "  <g id=\"fixtures\" stroke=\"#6b8f3a\" stroke-width=\"2\" fill=\"none\">\n" +
    "    <circle cx=\"180\" cy=\"180\" r=\"45\"/>\n" +
    "    <ellipse cx=\"300\" cy=\"470\" rx=\"70\" ry=\"40\"/>\n" +
    "    <rect x=\"470\" y=\"120\" width=\"180\" height=\"60\"/>\n" +
    "    <rect x=\"470\" y=\"500\" width=\"180\" height=\"60\"/>\n" +
    "    <polygon points=\"770,120 870,120 870,200 820,240 770,200\"/>\n" +
    "  </g>\n" +
    "\n" +
    "  <g id=\"curved\" stroke=\"#8a4fb5\" stroke-width=\"3\" fill=\"none\" stroke-dasharray=\"6,4\">\n" +
    "    <path d=\"M 470 250 C 520 200, 600 200, 650 250\"/>\n" +
    "    <path d=\"M 470 320 A 90 60 0 0 1 650 320\"/>\n" +
    "    <path d=\"M 760 400 Q 820 340, 880 400 T 880 520\"/>\n" +
    "  </g>\n" +
    "\n" +
    "  <g id=\"annotations\" stroke=\"#9a9aa2\" stroke-width=\"1\" fill=\"none\" stroke-dasharray=\"3,3\">\n" +
    "    <polyline points=\"80,660 400,660\"/>\n" +
    "    <polyline points=\"440,660 680,660\"/>\n" +
    "    <polyline points=\"720,660 920,660\"/>\n" +
    "  </g>\n" +
    "</svg>\n" +
    "\n"
}
