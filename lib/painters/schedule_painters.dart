import 'package:flutter/material.dart';

/// Custom painter for drawing the current time indicator line
class CurrentTimeLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const CurrentTimeLinePainter({
    this.color = Colors.red,
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Draw dashed line
    const dashWidth = 8.0;
    const dashSpace = 4.0;
    double startX = 0;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + dashWidth, 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }

    // Draw circles at both ends
    final circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(0, 0), 4, circlePaint); // Left circle
    canvas.drawCircle(Offset(size.width, 0), 4, circlePaint); // Right circle
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for creating dotted border effect on removed events
class DottedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  const DottedBorderPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.dashLength = 3.0,
    this.gapLength = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Create dotted border path
    final path = Path();

    // Top border
    double currentX = 0;
    while (currentX < size.width) {
      path.moveTo(currentX, 0);
      path.lineTo((currentX + dashLength).clamp(0, size.width), 0);
      currentX += dashLength + gapLength;
    }

    // Right border
    double currentY = 0;
    while (currentY < size.height) {
      path.moveTo(size.width, currentY);
      path.lineTo(size.width, (currentY + dashLength).clamp(0, size.height));
      currentY += dashLength + gapLength;
    }

    // Bottom border
    currentX = size.width;
    while (currentX > 0) {
      path.moveTo(currentX, size.height);
      path.lineTo((currentX - dashLength).clamp(0, size.width), size.height);
      currentX -= dashLength + gapLength;
    }

    // Left border
    currentY = size.height;
    while (currentY > 0) {
      path.moveTo(0, currentY);
      path.lineTo(0, (currentY - dashLength).clamp(0, size.height));
      currentY -= dashLength + gapLength;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
