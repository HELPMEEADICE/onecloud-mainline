#!/usr/bin/env python3
"""Headless EGL/GLES2 smoke test for the lima DRM driver."""
import ctypes

egl = ctypes.CDLL("libEGL.so.1")
gl = ctypes.CDLL("libGLESv2.so.2")

def fn(lib, name, restype, argtypes):
    f = getattr(lib, name)
    f.restype = restype
    f.argtypes = argtypes
    return f

eglGetProcAddress = fn(egl, "eglGetProcAddress", ctypes.c_void_p, [ctypes.c_char_p])
eglInitialize = fn(egl, "eglInitialize", ctypes.c_uint,
                   [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)])
eglQueryString = fn(egl, "eglQueryString", ctypes.c_char_p, [ctypes.c_void_p, ctypes.c_int])
eglBindAPI = fn(egl, "eglBindAPI", ctypes.c_uint, [ctypes.c_uint])
eglChooseConfig = fn(egl, "eglChooseConfig", ctypes.c_uint,
                     [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_void_p),
                      ctypes.c_int, ctypes.POINTER(ctypes.c_int)])
eglCreateContext = fn(egl, "eglCreateContext", ctypes.c_void_p,
                      [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_int)])
eglMakeCurrent = fn(egl, "eglMakeCurrent", ctypes.c_uint,
                    [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p])
eglGetError = fn(egl, "eglGetError", ctypes.c_int, [])

glGetString = fn(gl, "glGetString", ctypes.c_char_p, [ctypes.c_uint])
glGetError = fn(gl, "glGetError", ctypes.c_uint, [])
glGenFramebuffers = fn(gl, "glGenFramebuffers", None, [ctypes.c_int, ctypes.POINTER(ctypes.c_uint)])
glBindFramebuffer = fn(gl, "glBindFramebuffer", None, [ctypes.c_uint, ctypes.c_uint])
glGenRenderbuffers = fn(gl, "glGenRenderbuffers", None, [ctypes.c_int, ctypes.POINTER(ctypes.c_uint)])
glBindRenderbuffer = fn(gl, "glBindRenderbuffer", None, [ctypes.c_uint, ctypes.c_uint])
glRenderbufferStorage = fn(gl, "glRenderbufferStorage", None,
                           [ctypes.c_uint, ctypes.c_uint, ctypes.c_int, ctypes.c_int])
glFramebufferRenderbuffer = fn(gl, "glFramebufferRenderbuffer", None,
                               [ctypes.c_uint, ctypes.c_uint, ctypes.c_uint, ctypes.c_uint])
glCheckFramebufferStatus = fn(gl, "glCheckFramebufferStatus", ctypes.c_uint, [ctypes.c_uint])
glViewport = fn(gl, "glViewport", None, [ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int])
glClearColor = fn(gl, "glClearColor", None, [ctypes.c_float, ctypes.c_float, ctypes.c_float, ctypes.c_float])
glClear = fn(gl, "glClear", None, [ctypes.c_uint])
glFinish = fn(gl, "glFinish", None, [])
glReadPixels = fn(gl, "glReadPixels", None,
                  [ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                   ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p])

EGL_PLATFORM_SURFACELESS_MESA = 0x31DD
EGL_OPENGL_ES_API = 0x30A0
EGL_SURFACE_TYPE = 0x3033
EGL_PBUFFER_BIT = 0x0001
EGL_RENDERABLE_TYPE = 0x3040
EGL_OPENGL_ES2_BIT = 0x0004
EGL_NONE = 0x3038
EGL_CONTEXT_CLIENT_VERSION = 0x3098

get_platform_display = ctypes.CFUNCTYPE(
    ctypes.c_void_p, ctypes.c_uint, ctypes.c_void_p, ctypes.POINTER(ctypes.c_int))(
        eglGetProcAddress(b"eglGetPlatformDisplayEXT"))
dpy = get_platform_display(EGL_PLATFORM_SURFACELESS_MESA, None, None)
if not dpy:
    raise SystemExit("eglGetPlatformDisplayEXT failed")
major, minor = ctypes.c_int(), ctypes.c_int()
if not eglInitialize(dpy, ctypes.byref(major), ctypes.byref(minor)):
    raise SystemExit(f"eglInitialize failed: 0x{eglGetError():x}")
print(f"EGL {major.value}.{minor.value} vendor={eglQueryString(dpy, 0x3053).decode()}")

if not eglBindAPI(EGL_OPENGL_ES_API):
    raise SystemExit("eglBindAPI failed")
attrs = (ctypes.c_int * 7)(EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
                            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                            EGL_NONE, 0, 0)
config = ctypes.c_void_p()
n = ctypes.c_int()
if not eglChooseConfig(dpy, attrs, ctypes.byref(config), 1, ctypes.byref(n)) or n.value < 1:
    raise SystemExit("eglChooseConfig failed")
ctx_attrs = (ctypes.c_int * 3)(EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE)
ctx = eglCreateContext(dpy, config, None, ctx_attrs)
if not ctx:
    raise SystemExit(f"eglCreateContext failed: 0x{eglGetError():x}")
if not eglMakeCurrent(dpy, None, None, ctx):
    raise SystemExit(f"eglMakeCurrent failed: 0x{eglGetError():x}")

print("GL_VENDOR:", glGetString(0x1F00).decode())
print("GL_RENDERER:", glGetString(0x1F01).decode())
print("GL_VERSION:", glGetString(0x1F02).decode())
print("GL_SHADING_LANGUAGE_VERSION:", glGetString(0x8B8C).decode())

vendor = glGetString(0x1F00).decode().lower()
renderer = glGetString(0x1F01).decode().lower()
if "lima" not in vendor or "mali" not in renderer:
    raise SystemExit(f"not using lima/Mali: vendor={vendor!r} renderer={renderer!r}")

fbo, rb = ctypes.c_uint(), ctypes.c_uint()
glGenFramebuffers(1, ctypes.byref(fbo))
glBindFramebuffer(0x8D40, fbo.value)
glGenRenderbuffers(1, ctypes.byref(rb))
glBindRenderbuffer(0x8D41, rb.value)
glRenderbufferStorage(0x8D41, 0x8058, 64, 64)  # GL_RGBA8
glFramebufferRenderbuffer(0x8D40, 0x8CE0, 0x8D41, rb.value)  # COLOR_ATTACHMENT0
status = glCheckFramebufferStatus(0x8D40)
if status != 0x8CD5:
    raise SystemExit(f"framebuffer incomplete: 0x{status:x}")
glViewport(0, 0, 64, 64)
glClearColor(0.25, 0.5, 0.75, 1.0)
glClear(0x4000)  # GL_COLOR_BUFFER_BIT
glFinish()
pixel = (ctypes.c_ubyte * 4)()
glReadPixels(0, 0, 1, 1, 0x1908, 0x1401, pixel)  # GL_RGBA, GL_UNSIGNED_BYTE
print("cleared pixel RGBA:", list(pixel), "glGetError: 0x%x" % glGetError())
if list(pixel) != [64, 128, 191, 255]:
    raise SystemExit("unexpected pixel value")
print("RESULT: lima EGL/GLES2 rendering OK")
