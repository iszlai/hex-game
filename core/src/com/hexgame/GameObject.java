package com.hexgame;

import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.Sprite;

import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/**
 * Created by Lehel on 3/17/2016.
 */
public class GameObject extends Sprite {


    public final GridLocation location;
    public boolean clickable=true;
    public Map<GridLocation,GameObject> grid;

    public GameObject(Texture texture, GridLocation location,Map<GridLocation,GameObject> grid) {
        super(texture);
        this.location=location;
        this.grid=grid;
    }


    public Set<GameObject> getAvailableNeighbours() {
        Set<GameObject> res=new HashSet<GameObject>();
        for (Sides side: Sides.values() ) {
            GridLocation neighbour = location.getNeighbour(side);
            res.add(grid.get(neighbour));
        }
    return res;
    }

}
