precision mediump float;

uniform sampler2D texture;

varying vec4 v_col;
varying vec2 v_uv;

void main()
{
		gl_FragColor = v_col;
}
