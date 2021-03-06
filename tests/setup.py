from setuptools import setup, Extension
from Cython.Build import cythonize
import numpy

extensions = [
    Extension("splitter_test", ["splitter_test.pyx"],
        extra_compile_args=["-g"],  # maybe unnecessary.
        extra_link_args=["-g"],
        # define_macros=[  # Causes error.
        #     ("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")
        # ],
    ),
#    Extension("patched_modules._criterion", ["patched_modules/_criterion.pyx"],
#        extra_compile_args=["-g"],
#        extra_link_args=["-g"],
#    ),
#    Extension("patched_modules._splitter", ["patched_modules/_splitter.pyx"],
#        extra_compile_args=["-g"],
#        extra_link_args=["-g"],
#    )
]

setup(
    name='hypertrees tests',
    ext_modules=cythonize(
        extensions,
        gdb_debug=True,
        annotate=True,
        # language="c++",
        language_level="3",
    ),
    include_dirs=[numpy.get_include()],
)
