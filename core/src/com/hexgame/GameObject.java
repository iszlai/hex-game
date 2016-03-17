package com.hexgame;

import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.Sprite;

/**
 * Created by Lehel on 3/17/2016.
 */
public class GameObject extends Sprite {
    public final int gridX;
    public final int gridY;

    public GameObject(Texture texture, int gridX, int gridY) {
        super(texture);
        this.gridX = gridX;
        this.gridY = gridY;

    }

}
