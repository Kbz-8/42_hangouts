#version 100

precision mediump float;

attribute vec2 a_pos;
attribute vec4 a_col;
attribute vec2 a_uv;

uniform vec2 u_screen;

varying vec4 v_col;
varying vec2 v_uv;

void main()
{
	// Convert top-left pixel coords to NDC
	vec2 ndc = vec2(
		(a_pos.x / u_screen.x) * 2.0 - 1.0,
		1.0 - (a_pos.y / u_screen.y) * 2.0
	);
	gl_Position = vec4(ndc, 0.0, 1.0);
	v_col = a_col;
	v_uv = a_uv;
}
