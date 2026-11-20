---
name: docstring
description: House conventions for Python docstrings (NumPy style) and for section-divider comments in code. Use when writing, editing or reviewing docstrings for Python modules, classes, functions or methods, or when the user mentions docstrings, NumPy style, or documenting code.
---

# Docstrings

Write every Python module, class, function and method docstring in NumPy style,
with these house rules:

- Open with `"""` on its own line. The summary goes on the next line: at most
  79 characters, ending with a period.
- Classes: list public attributes in an `Attributes` section of the class
  docstring. Document constructor arguments in `__init__`'s own docstring,
  under `Parameters`.
- Optional parameters: `name : type, optional`, and end the description with
  `Default is <value>.`
- Arrays: give the shape in the description, using the code's own symbols:
  `of shape (n, d)`, `length K`.
- Several return values: name each one (`selected : list of int`). Say when a
  value can be `None`.

## Class template

```python
class MyClass:
    """
    One-line summary of the class.

    Attributes
    ----------
    attr1 : type
        Description of attr1.
    """

    def __init__(self, param1, param2=None):
        """
        Initialize the class.

        Parameters
        ----------
        param1 : type
            Description of param1.
        param2 : type, optional
            Description of param2. Default is None.
        """
```

## Method example

```python
    def _greedy_select(self, gram_matrix_sobolev_np, raw_sensitivities_np):
        """
        Greedy forward selection of basis vectors by Gram-Schmidt.

        Parameters
        ----------
        gram_matrix_sobolev_np : numpy.ndarray
            Gram matrix of shape (K, K) defining the inner product used for
            orthogonalization and normalization.
        raw_sensitivities_np : numpy.ndarray
            Raw sensitivities used to score candidates, length K.

        Returns
        -------
        basis_coefs_sel : numpy.ndarray or None
            Selected coefficient vectors, of shape (K, m) where m is the
            number selected. None if no vector is selected.
        selected : list of int
            Indices of the selected basis vectors.
        sensitivities_sel : numpy.ndarray
            Sensitivities of the selected vectors, length m.
        """
```

## Section dividers

To divide code into sub-blocks, use exactly:

```python
### ---------------------------------------------------------------------------
### Header
### ---------------------------------------------------------------------------
```
