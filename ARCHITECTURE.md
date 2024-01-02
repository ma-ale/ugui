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

```text
                         parent div
[0,0]->+------------------------------------------------+
       |                                                |
       |                                                |
       |                                                |
       |                                                |
       |                                                |
       |                                                |
       |                                                |
       |                   space_r                      |
       |                   space_c                      | begin div1
       |                                                | ----+
       |                                                |     |
       |                                                |     |
       |                                                |     |
       |                                                |     |
       |                                                |     |
       |                                                |     |
       |                                                |     |
       +------------------------------------------------+     |
                                                              |
                                                              |
                         parent div                           |
[0,0]->+----------------------+-------------------------+     |
       |                      |                         |     |
       |                      |                         |     |
       |                      |                         | <---+
       |        div 1         |                         | end div1
       |                      |                         |
       |                      |                         |
       |                      |                         |
       |                      |                         |
       +----------------------+          space_r        |
       |                      |                         |
       |                      |                         | begin div2
       |                      |                         | ----+
       |                      |                         |     |
       |       space_c        |                         |     |
       |                      |                         |     |
       |                      |                         |     |
       |                      |                         |     |
       +----------------------+-------------------------+     |
                                                              |
                                                              |
                         parent div                           |
[0,0]->+----------------------+--------+----------------+     |
       |                      |        |                |     |
       |                      | div 2  |                |     |
       |                      |        |                |     |
       |       div 1          +--------+                |     |
       |                      |xxxxxxxx|                |     |
       |                      |xxxxxxxx|                | <---+
       |                      |xxxxxxxx|                | end div2
       |                      |xxxxxxxx|                |
       +----------------------+--------+    space_r     |
       |                               |                |
       |                               |                |
       |                               |                |
       |                               |                |
       |             space_c           |                |
       |                               |                |
       |                               |                |
       |                               |                |
       +-------------------------------+----------------+

           +-+
           |x|: Lost Space
           +-+
```

TODO: handle when the content overflows the div
- Use a different concept, like a view or relative space, for example the child
div could have position `[0,0]` but in reality it is relative to the origin of the
parent div
- each div could have a view and a total area of the content, when drawing everything
is clipped to the view and scrollbars are shown
- individual elements accept dimensions and the x/y coordinates could be interpreted
as offset if the layout is row/column or absolute coordinates if the leayout is floating

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
