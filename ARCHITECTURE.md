## High level overview

Under the hood every element has an id, this id allows the library to store state
between frames.
Elements are also cached such that when the ui tree is rebuilt at the beginning of
every frame the element data structure doesn't have to be rebuilt.

Elements are arranged in a tree, nodes are container elements that can contain other
elements, leafs are elements that cannot contain other elements.

Every element has a size and a position, containers also have to keep track of their
layout information and some other state.

Elements can push commands into the draw stack, which is a structure that contains
all the draw commands that the user application has to perform do display the ui
correctly, such commands include drawing lines, rectangles, sprites, text, etc.


```text
            +-----------+
            | ug_init() |
            +-----+-----+
                  |
                  |
                  |
        +---------v----------+
        |ug_input_keyboard() |
        |ug_input_mouse()    <----+
        |ug_input_clipboard()|    |
        |        ...         |    |
        +---------+----------+    |
                  |               |
                  |               |
          +-------v--------+      |
          |ug_frame_begin()|      |
          +-------+--------+      |
                  |               |
                  |               |
        +---------v----------+    |
        |ug_window_start()   |    |
   +---->ug_container_start()|    |
   |    |ug_div_start()      |    |
   |    |        ...         |    |
   |    +---------+----------+    |
   |              |               |
   |              |               |
multiple +--------v---------+     |
 times   |ug_layout_row()   |     |
   |     |ug_layout_column()|     |
   |     |ug_layout_float() |     |
   |     |       ...        |     |
   |     +--------+---------+     |
   |              |               |
   |              |               |
   |       +------v------+        |
   |       |ug_button()  |        |
   |       |ug_text_box()|        |
   |       |ug_slider()  |        |
   |       |     ...     |        |
   |       +------+------+        |
   |              |               |
   +--------------+               |
                  |               |
         +--------v---------+     |
         |ug_window_end()   |     |
         |ug_container_end()|     |
         |ug_div_end()      |     |
         |       ...        |     |
         +--------+---------+     |
                  |               |
                  |               |
                  |               |
           +------v-------+       |
           |ug_frame_end()|       |
           +------+-------+       |
                  |               |
                  |               |
                  |               |
           +------v-------+       |
           |user draws the|       |
           |      ui      +-------+
           +------+-------+
                  |
                  |quit
                  |
           +------v-------+
           | ug_destroy() |
           +--------------+
```

### Layouting

Layouting happens in a dynamic grid, when a new element is inserted in a non-floating
manner it reserves a space in the grid, new elements are placed following this grid.

Every div has two points of origin, one for the row layout and one for the column
layout, named origin_r and origin_c respectively

origin_r is used when the row layout is used and it is used to position the child
elements one next to the other, as such it always points to the top-right edge
of the last row element

```text
Layout: row
#: lost space
              Parent div
x---------------------------------+
|[origin_c]                       |
|[origin_r]                       |
|                                 |
|                                 |
|                                 |
|                                 |
|                                 |
|                                 |
|                                 |
+---------------------------------+

              Parent div
+-----x---------------------------+
|     |[origin_r]                 |
| E1  |                           |
|     |                           |
x-----+---------------------------+
|[origin_c]                       |
|     |                           |
|     |                           |
|     |                           |
|     |                           |
|     |                           |
+-----+---------------------------+

              Parent div
+-----+----------+-----x----------+
|     |    E2    |     |[origin_r]|
|  E1 +----------+     |          |
|     |##########| E3  |          |
+-----+##########|     |          |
|################|     |          |
+----------------x-----+----------+
|                [origin_c]       |
|                |                |
|                |                |
|                |                |
+----------------+----------------+
```

TODO: handle when the content overflows the div
- Use a different concept, like a view or relative space, for example the child
div could have position `[0,0]` but in reality it is relative to the origin of the
parent div
- each div could have a view and a total area of the content, when drawing everything
is clipped to the view and scrollbars are shown
- individual elements accept dimensions and the x/y coordinates could be interpreted
as offset if the layout is row/column or absolute coordinates if the leayout is floating

A div can be marked resizeable or fixed, and static or dynamic. The difference being
that resizeable adds a resize handle to the div and dynamic lets the content overflow
causing scrollbars to be drawn

### Notes

How elements determine if they have focus or not

```C
// in begin_{container} code
calculate focus
set has_focus property



// in the element code
if(PARENT_HAS_FOCUS()) {
	update stuff
} else {
	fast path to return
}
```

How to get ids:
	1. use a name for each element
	2. supply an id for each element
	3. use a macro and the line position as id and then hash it
	4. use a macro, get the code line and hash it
