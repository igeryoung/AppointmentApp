import React, { useEffect, useRef } from 'react';
import type { NotePage, Stroke } from '../types';

interface HandwritingCanvasProps {
  page: NotePage;
  width?: number;
  height?: number;
  sourceWidth?: number;
  sourceHeight?: number;
  className?: string;
}

/**
 * Read-only canvas component for rendering handwritten notes
 * Displays strokes with proper colors, widths, and types (pen/highlighter)
 */
export const HandwritingCanvas: React.FC<HandwritingCanvasProps> = ({
  page,
  width = 800,
  height = 600,
  sourceWidth,
  sourceHeight,
  className = '',
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const canvasWidth = sourceWidth ?? width;
  const canvasHeight = sourceHeight ?? height;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Clear canvas
    ctx.clearRect(0, 0, canvasWidth, canvasHeight);

    // Set canvas background to white
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvasWidth, canvasHeight);

    // Separate strokes by type for proper z-ordering
    const highlighters: Stroke[] = [];
    const pens: Stroke[] = [];

    for (const stroke of page) {
      if (stroke.strokeType === 'highlighter') {
        highlighters.push(stroke);
      } else {
        pens.push(stroke);
      }
    }

    // Draw highlighters first (background layer)
    highlighters.forEach((stroke) => drawStroke(ctx, stroke));

    // Draw pens on top (foreground layer)
    pens.forEach((stroke) => drawStroke(ctx, stroke));
  }, [page, canvasWidth, canvasHeight]);

  /**
   * Draw a single stroke on the canvas
   */
  const drawStroke = (ctx: CanvasRenderingContext2D, stroke: Stroke) => {
    if (stroke.points.length === 0) return;

    const color = argbToRgba(stroke.color, stroke.strokeType === 'highlighter');

    ctx.strokeStyle = color;
    ctx.lineWidth = stroke.strokeWidth;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    // For highlighters, use lighter compositing
    if (stroke.strokeType === 'highlighter') {
      ctx.globalCompositeOperation = 'multiply';
      ctx.globalAlpha = 0.4;
    } else {
      ctx.globalCompositeOperation = 'source-over';
      ctx.globalAlpha = 1.0;
    }

    ctx.beginPath();

    // Move to first point
    const firstPoint = stroke.points[0];
    ctx.moveTo(firstPoint.dx, firstPoint.dy);

    // Draw lines between points
    for (let i = 1; i < stroke.points.length; i++) {
      const point = stroke.points[i];
      ctx.lineTo(point.dx, point.dy);
    }

    ctx.stroke();

    // Reset composite operation and alpha
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1.0;
  };

  /**
   * Convert ARGB integer to CSS rgba string
   * @param argb - ARGB color as 32-bit integer
   * @param isHighlighter - Whether this is a highlighter (adds transparency)
   */
  const argbToRgba = (argb: number, isHighlighter: boolean = false): string => {
    const a = (argb >> 24) & 0xff;
    const r = (argb >> 16) & 0xff;
    const g = (argb >> 8) & 0xff;
    const b = argb & 0xff;

    const alpha = isHighlighter ? 0.4 : a / 255;

    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  };

  return (
    <canvas
      ref={canvasRef}
      width={canvasWidth}
      height={canvasHeight}
      className={className}
      style={{
        border: '1px solid #e5e7eb',
        borderRadius: '0.375rem',
        backgroundColor: '#ffffff',
      }}
    />
  );
};
