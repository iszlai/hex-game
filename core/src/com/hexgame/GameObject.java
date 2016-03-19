package com.hexgame;

import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.Sprite;

/**
 * Created by Lehel on 3/17/2016.
 */
public class GameObject extends Sprite {


    public final GridLocation location;
    public boolean clickable=true;

    public GameObject(Texture texture, GridLocation location) {
        super(texture);
        this.location=location;
    }






}
