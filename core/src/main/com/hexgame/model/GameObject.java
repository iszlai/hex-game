package com.hexgame.model;

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
    public Map<GridLocation,GameObject> grid;
    public boolean clickable=true;
    public boolean walkAble=false;

    public GameObject(Texture texture, GridLocation location,Map<GridLocation,GameObject> grid) {
        super(texture);
        this.location=location;
        this.grid=grid;
    }


    public Set<GameObject> getAvailableNeighbours() {
        Set<GameObject> res=new HashSet<GameObject>();
        for (Sides side: Sides.values() ) {
            GridLocation neighbour = location.getNeighbour(side);
            GameObject gameObject = grid.get(neighbour);
            if(gameObject!=null&&gameObject.walkAble){
                res.add(gameObject);
            }
        }
    return res;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;

        GameObject that = (GameObject) o;

        if (clickable != that.clickable) return false;
        return !(location != null ? !location.equals(that.location) : that.location != null);

    }

    @Override
    public int hashCode() {
        int result = location != null ? location.hashCode() : 0;
        result = 31 * result + (clickable ? 1 : 0);
        return result;
    }



}
