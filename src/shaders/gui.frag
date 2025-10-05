precision mediump float;

uniform sampler2D u_texture;

varying vec4 v_col;
varying vec2 v_uv;
varying float v_is_textured;

void main()
{
	if(v_is_textured != 0.0)
		gl_FragColor = v_col * texture2D(u_texture, v_uv);
	else
		gl_FragColor = v_col;
}
