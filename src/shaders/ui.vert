#version 100

attribute vec2 aPos;
attribute vec3 aColor;

varying vec3 vColor;

uniform mat4 proj;
uniform mat4 model;

void main()
{
	vColor = aColor;
    gl_Position = proj * model * vec4(aPos, 0.0, 1.0);
}
